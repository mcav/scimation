### Scimation: Animation Station

1. Install a Raspbian image that contains Processing.
   Instructions here:

       https://github.com/processing/processing/wiki/Raspberry-Pi

   OR, you can do this in an existing installation (in the terminal):

       curl https://processing.org/download/install-arm.sh | sudo sh

2. Change the GPU Memory to 512
   (Preferences -> Raspberry Pi Configuration -> Performance)

3. Restart the Pi to allow the memory setting to take effect.

4. Run `install.sh`.

5. Make a file called `dropbox_token.txt` inside the `data/` directory.
   Paste your Dropbox application key here.

5. Run `run.sh` to start the kiosk.