# Overview

Help me make a quick mobile app for taking gps tracks (running) and
showing on a map. This will initially be Android only app.

## Claude Spec

- You are a mobile developer expert. You have knowledge of python, C# and flutter and Android dev.

## Task

- We will be making an Android phone app for collecting GPS data while
  running.
- We will use sqlite as a single db store for our application state.
- We will start off developing via python mobile. We may switch to
  other technologies like NET MAUI or Flutter.
    - We've agreed Flutter now.

## Openstreetmap

- I intent to use Openstreetmap tile servers for showing some map info.
    - See https://wiki.openstreetmap.org/wiki/Raster_tile_providers
    - We will use the tile server https://tile.openstreetmap.org/{z}/{x}/{y}.png.
    - We must cache map tiles in our sqlite db to reduce load on their
      server. We must have a max size of our cache like 50MB, with older
      tiles dropping out, and a caching policy (7 days age - after 7 days
      we will invalidate and reload these cache tiles if we are able to
      download new ones).

## App Spec

- App creates a local sqlite db if not present at startup, with all the
  relevant tables created if missing.
    - There will be a debug function - db - that shows the status of the
      db via a button press.

