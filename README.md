## Synopsis

Camera control for a logitech QuickCam PTZ (and hopefully others), including Tilt, Pan, and image controls such as Brightness, Contrast.

## Motivation

I have that old camera that supports Tilt and Pan, but I had no way to control the motor movement.
What better excuse to play with Ruby and Tk?

## Installation

You need **uvcdynctrl**. This is what does the actual communication with the camera.
Beyound that it is self contained, so you can just clone the project or download it.

## Tests

This is a personal project, so I'm not writing any tests. This works with Ruby 1.9 on Linux Mint.
Not sure about 2.x Ruby since Tk is now a gem and I had some issue installing it.

## License

