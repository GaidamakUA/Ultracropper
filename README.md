# Ultracropper

Ultracropper is a small native macOS app for cropping an image and fixing its perspective by dragging four corners.

It uses only Apple frameworks: SwiftUI, AppKit, Core Image, and ImageIO. Processing happens locally and the app has no network dependency.

## Features

- Open common image formats from the app or Finder's **Open With** menu
- Position a perspective crop using four precise corner handles
- Pinch to zoom from 1× to 8×
- Preview the corrected image before saving
- Export an opaque, sRGB JPEG at 90% quality as `original-name_fixed.jpg`

## Requirements

- macOS 26.1 or later
- Xcode 26.1 or later to build from source

## Build and install

1. Open `Ultracropper.xcodeproj` in Xcode.
2. Select the **Ultracropper** scheme and **My Mac** destination.
3. Press **Command-R** to build and run it.
4. Choose **Product → Show Build Folder in Finder**.
5. Open `Products/Debug` and drag `Ultracropper.app` into `/Applications`.
6. Launch the installed app once so Finder registers it.

You can then right-click an image and choose **Open With → Ultracropper**.

## Usage

1. Open an image.
2. Drag the four blue handles onto the desired corners.
3. Switch to **Preview** to inspect the result.
4. Click **Save** and choose where to write the suggested `_fixed.jpg` file.

## Development note

This project was vibe-coded. The product direction came from a human, while much of the implementation was produced iteratively with AI assistance. Review the code before relying on it for important workflows.

## Homebrew

If there is enough interest, Ultracropper may be published as a Homebrew Cask. Open an issue or leave a reaction to show that a `brew install --cask ultracropper` option would be useful.
