import java.nio.file.*;
import java.util.concurrent.*;
import java.util.*;
import java.io.*;

class VideoEncoder implements Callable<Path> {
  Path directory; 
  String imagePathFormat;
  int fps;

  public VideoEncoder(Path directory, String imagePathFormat, int fps) {
    this.directory = directory;
    this.imagePathFormat = imagePathFormat;
    this.fps = fps;
  }

  public Path call() {
    boolean isMac = System.getProperty("os.name").equals("Mac OS X");

    Path outPath = directory.resolve("out.mp4");

    ArrayList<String> strs = new ArrayList<String>();
    strs.add(isMac ? "/usr/local/bin/avconv" : "/usr/bin/avconv");
    strs.add("-f");
    strs.add("image2");
    strs.add("-framerate");
    strs.add("" + fps);
    strs.add("-i");
    strs.add(imagePathFormat);
    strs.add("-vcodec");
    strs.add("libx264");
    strs.add("-y"); // overwrite output file

    try {
      strs.add(outPath.toFile().getCanonicalPath());

      ProcessBuilder pb = new ProcessBuilder(strs);
      pb.directory(directory.toFile());
      pb.redirectOutput(ProcessBuilder.Redirect.INHERIT);
      pb.redirectError(ProcessBuilder.Redirect.INHERIT);
      Process p = pb.start();
      p.getOutputStream().close();
      if (p.waitFor() != 0) {
        throw new Exception("Video encoding failed!");
      }
    } 
    catch (Exception e) {
      throw new RuntimeException(e);
    }
    return outPath;
  }
}