import com.dropbox.core.DbxRequestConfig;
import com.dropbox.core.v2.DbxClientV2;
import java.util.concurrent.*;
import java.nio.file.*;
import java.io.*;

class DropboxUploader implements Callable<Boolean> {
  String accessToken;
  Path localPath;
  String dropboxFilename;

  public DropboxUploader(String accessToken, Path localPath, String dropboxFilename) {
    this.accessToken = accessToken;
    this.localPath = localPath;
    this.dropboxFilename = dropboxFilename;
  }

  public Boolean call() {
    try {
      InputStream is = new FileInputStream(this.localPath.toFile());    
      DbxClientV2 dropbox = new DbxClientV2(new DbxRequestConfig("DropboxUploader"), accessToken);            
      System.out.println("Uploading to Dropbox...");
      dropbox.files().uploadBuilder(dropboxFilename).uploadAndFinish(is);
      is.close();
    } 
    catch (Exception e) {
      System.out.println(e);
      return false;
    }
    return true;
  }
}