import gohai.glvideo.*;
import java.awt.image.BufferedImage;
import javax.imageio.ImageIO;
import javax.imageio.stream.*;
import processing.io.*;
import java.util.*;
import java.text.*;
import java.io.*;
import java.nio.file.*;
import java.nio.file.attribute.*;
import java.util.concurrent.*;

final int MAX_IMAGES_ALLOWED = 200;
final int FPS = 10;
final int THROTTLE_CAPTURE_MS = 100; // Don't allow repeated captures faster than this many milliseconds.
final int TIME_TO_DISPLAY_FINAL_ANIMATION_MS = 60000;
final int MIN_PICS_NEEDED_TO_UPLOAD = 5;

final String IMAGE_PATH_FORMAT = "img%04d.jpg";

// RPI GPIO button configurations:
final int PIN_OK = 17;
final int PIN_UNDO = 22;
final int PIN_DONE = 18;

enum State {
  INTRO, CAPTURING, DONE
}

State state = State.INTRO;
GLCapture cam;
PImage introImage;
PImage endImage;
PImage bannerImage;
PImage currentPreviewImage;
PImage renderingImage;
GLMovie completedVideo;
ExecutorService executor;
Future<Path> localVideoPathFuture;
String dropboxToken;

int pendingPinPress = 0; // If a button has been pressed, process it in the next draw() call.
int lastPinPressTime; // The timestamp of the last time we pressed "capture", to rate-limit snapshots.
float lastFlashTime = 0;
PImage onionImage;
int imageCount = 0;
int timeFinished; // The time the animation was completed
Path currentAnimationDir; // Each session gets a new temporary folder.

void setup() {
  // Prepare the screen; the P2D renderer is hardware-accelerated.
  fullScreen(P2D);
  //frameRate(20); // This is the framerate of everything, not really the animation, but no need to go faster
  noCursor(); // Hide the mouse.

  // Prepare the camera, GPIO pins (if applicable), and the location of "avconv" (which encodes mp4 files).
  String[] devices = GLCapture.list();
  if (System.getProperty("os.name").equals("Mac OS X")) {
    cam = new GLCapture(this, devices[0], 1280, 720, 10);
  } else {
    // I'm assuming we're on Raspberry Pi here!
    GPIO.pinMode(PIN_OK, GPIO.INPUT);
    GPIO.pinMode(PIN_UNDO, GPIO.INPUT);
    GPIO.pinMode(PIN_DONE, GPIO.INPUT);
    try {
      Runtime.getRuntime().exec("gpio -g mode " + PIN_OK + " up");
      Runtime.getRuntime().exec("gpio -g mode " + PIN_UNDO + " up");
      Runtime.getRuntime().exec("gpio -g mode " + PIN_DONE + " up");
    } 
    catch (IOException e) {
      System.out.println(e);
    }
    GPIO.attachInterrupt(PIN_OK, this, "gpioPressed", GPIO.FALLING);
    GPIO.attachInterrupt(PIN_UNDO, this, "gpioPressed", GPIO.FALLING);
    GPIO.attachInterrupt(PIN_DONE, this, "gpioPressed", GPIO.FALLING);
    // The RPi is still pretty limited, performance-wise; 640x380 may be the best we can get.
    // (Only certain resolution numbers work; you can't just pick arbitrary numbers.)
    cam = new GLCapture(this, devices[0], 640, 380, /* fps: */ 10);
  }

  introImage = requestImage("intro_screen.png");
  endImage = requestImage("end_screen.png");
  bannerImage = requestImage("banner.png");
  renderingImage = requestImage("rendering.png");
  executor = Executors.newSingleThreadExecutor();
  dropboxToken = loadStrings("dropbox-token.txt")[0]; 

  cam.play(); // Start capturing images from the camera. We'll do this constantly.

  toIntro();
}

Path getDiskImagePath(int imageNumber) {
  return currentAnimationDir.resolve(String.format(IMAGE_PATH_FORMAT, imageNumber));
}

///////////////////////////////////////////////////////////////////////////////
// KEY HANDLING:
//  - We handle BACKSPACE, ENTER, and SPACE as virtual "buttons".
//  - ESC (to abort the program) is handled by Processing.
//  - We handle keyboard presses in keyPressed(), GPIO buttons in gpioPressed(),
//    and delegate the real logic to handleKey().

void keyPressed() {
  if (key == BACKSPACE) {
    handleKey(PIN_UNDO);
  } else if (key == ' ') {
    handleKey(PIN_OK);
  } else if (key == ENTER) {
    handleKey(PIN_DONE);
  } else {
    handleKey(PIN_OK); // any key
  }
}

void gpioPressed(int pin) {
  GPIO.noInterrupts(); // avoid recursive calls
  // GPIO voltages apparently have some "noise". This callback gets called
  // when the state drops from 1 to 0, but before we say "hey, a button was pressed",
  // we check to make sure it stays at 0 for a few milliseconds, to avoid false positives. 
  int start = millis();
  while (millis() - start < 50) {
    if (GPIO.digitalRead(pin) != 0) {
      GPIO.interrupts();
      return;
    }
  }
  GPIO.interrupts();
  // Handle this press in the next draw() call.
  pendingPinPress = pin;
}

// Here's where we really handle keys!
void handleKey(int pin) {
  switch(state) {
  case INTRO:
    // On the intro screen, any key sends us to the capture screen.
    state = State.CAPTURING;
    break;

  case CAPTURING:
    if (pin == PIN_UNDO && imageCount > 0) {

      executor.submit(new Runnable() {
        public void run() {
          imageCount--;
          // Undo the last image.
          getDiskImagePath(imageCount).toFile().delete(); // Delete the file.
          try {
            if (imageCount >= 1) {
              onionImage = loadImage(getDiskImagePath(imageCount - 1).toFile().getCanonicalPath());
            } else {
              onionImage = null;
            }
          } 
          catch (IOException e) {
          }
        }
      }
      );
    } else if (pin == PIN_OK && currentPreviewImage != null) {
      // We don't want to overload the system by trying to capture super rapidly.
      if (millis() - lastPinPressTime < THROTTLE_CAPTURE_MS) {
        System.out.println("Ignoring press because it was too fast.");
        return;
      }
      lastPinPressTime = millis();
      // Save the current preview to memory and to disk.
      // Grab the absolute latest snapshot.
      if (cam.available()) {
        cam.read();
        currentPreviewImage = cam;
      }
      final PImage capturedImage = currentPreviewImage.copy();
      onionImage = capturedImage;
      executor.submit(new Runnable() {
        public void run() {
          try {
            capturedImage.save(getDiskImagePath(imageCount).toFile().getCanonicalPath());
            imageCount++;
            System.out.println("Got image #" + imageCount);
          } 
          catch (IOException e) {
            System.out.println(e);
          }
        }
      }
      );
      // Make a fake flash effect; this value (the amount of white) will quickly dissipate
      // thanks to logic in draw().
      lastFlashTime = millis();
      // If we've captured as many as memory will allow, we're done!
      if (imageCount + 1 >= MAX_IMAGES_ALLOWED) {
        toDone();
      }
    } else if (pin == PIN_DONE) {
      // Play the animation if they did some work.
      if (imageCount > 0) {
        toDone();
      } else {
        toIntro();
      }
    }
    break;
  case DONE:
    toIntro();
    break;
  }
}

// Go back to the intro screen.
// The on-disk files are cleaned up by the upload thread, because the upload process
// needs the disk files to create the movie.
void toIntro() {
  state = State.INTRO;
  imageCount = 0;   
  localVideoPathFuture = null;
  onionImage = null;
  if (completedVideo != null) {
    completedVideo.close();
  }
  completedVideo = null;
  // Give us a new temporary directory to work with; each session
  // gets a new one, so that it's easy to clear out old images.
  // Previous sessions' directories are cleaned up after each session and
  // won't be hanging around if everything is working properly.
  try {
    if (currentAnimationDir != null) {
      deleteDirectoryRecursively(currentAnimationDir);
    }
    currentAnimationDir = Files.createTempDirectory("scimation");
  } 
  catch (IOException e) {
    throw new RuntimeException(e);
  }
  // For good measure, take a moment to clean house:
  System.gc();
}

void toDone() {
  state = State.DONE;

  localVideoPathFuture = executor.submit(new VideoEncoder(currentAnimationDir, IMAGE_PATH_FORMAT, FPS));
}

void checkForVideoResult() {
  // If the video has finished encoding, voila, let's display it!
  if (localVideoPathFuture != null && completedVideo == null && localVideoPathFuture.isDone()) {
    try {
      Path localVideoPath = localVideoPathFuture.get();
      completedVideo = new GLMovie(this, localVideoPath.toFile().getCanonicalPath());
      completedVideo.loop();
      completedVideo.read();
      timeFinished = millis();

      if (imageCount > MIN_PICS_NEEDED_TO_UPLOAD) {
        String dateString = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss:SSS").format(new Date());
        executor.submit(new DropboxUploader(dropboxToken, localVideoPath, "/" + dateString + ".mp4"));
      } else {
        System.out.println("Not enough pics to consider uploading.");
      }
    } 
    catch (Exception e) {
    }
  }
}

void deleteDirectoryRecursively(Path directory) {
  try {
    Files.walkFileTree(directory, new SimpleFileVisitor<Path>() {
      @Override
        public FileVisitResult visitFile(Path file, BasicFileAttributes attrs) throws IOException {
        System.out.println("Deleting file " + file.toString());
        Files.delete(file);
        return FileVisitResult.CONTINUE;
      }

      @Override
        public FileVisitResult postVisitDirectory(Path dir, IOException exc) throws IOException {
        Files.delete(dir);
        return FileVisitResult.CONTINUE;
      }
    }
    );
  } 
  catch (IOException e) {
  }
}

// Rendering!
void draw() {
  background(0);

  // Since we can't handle GPIO presses in interrupts, handle it here:
  if (pendingPinPress > 0) {
    handleKey(pendingPinPress);
    pendingPinPress = 0;
  }

  switch(state) {

  case INTRO:
    image(introImage, 0, 0, width, height);
    break;

  case CAPTURING:
    // Grab another frame from the camera.
    if (cam.available() == true) {
      cam.read();
      currentPreviewImage = cam;
    }
    // Render the camera preview.
    if (currentPreviewImage != null) {
      image(currentPreviewImage, 0, 0, width, height);
    }
    // Render the onion skin.
    if (onionImage != null) {
      tint(255, 60);
      image(onionImage, 0, 0, width, height);
      noTint();
    }
    double halfLifeMs = 70;
    int flashEffectRemaining = (int)(255.0 * Math.pow(0.5, (millis() - lastFlashTime) / halfLifeMs)); 
    if (flashEffectRemaining > 0) {
      fill(255, (int)flashEffectRemaining);
      rect(0, 0, width, height);
    }
    // Render the banner overlay.
    image(bannerImage, 0, 0, width, height);
    break;

  case DONE:

    // Figure out which frame to display now...
    //int frame = int((timeElapsed / 1000.0) * FPS) % imageCount;

    checkForVideoResult();

    if (completedVideo != null) {
      if (completedVideo.available()) {
        completedVideo.read();
      }
      image(completedVideo, 0, 0, width, height);
      image(endImage, 0, 0, width, height);

      int timeElapsed = millis() - timeFinished;
      // If they've seen this animation long enough, reset the kiosk.
      if (timeElapsed > TIME_TO_DISPLAY_FINAL_ANIMATION_MS) {
        toIntro();
      }
    } else {
      image(renderingImage, 0, 0, width, height);
    }
    break;
  }
}