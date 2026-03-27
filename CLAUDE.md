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
- App needs to have GPS permissions from app. Add button to check this and
  give a message to say how the GPS permissions must be set up in the app,
  if they are wrong.
- App gps tracking
    - Button area of main screen - Record; Pause/Unpause (active if Record is
      active); Stop - which stops the session and saves all the gps data
      collected into a sqlite table.
    - Record here should also grab the time Record started, and store this
      in the sqlite table.
- App gps tracking > Show button
    - Show all previously recorded gps tracks as a little
      scrollable table with the data, and number of gps coordinates
      collected in each.
        - The table here show have a 'Copy' button against each entry.
          Clicking Copy show grab the gps data as a gpx trace xml file
          that can be paste elsewhere. NB: Would it be possible to also
          have a Save function, to save to a special place like Downloads
          or Documents?
        - The table should show a distance covered indicator, by drawing and
          summing a straight line between all gps coordinates.
        - The table should approximate speed in minutes per km.
    - Each track_events should be able to be renamed in this part of the app -
      we can use a Rename button and edit box here.
    - Have a delete button to delete track_events for each event. If clicked then
      show a 'do you really want to delete' type confirmation before actually
      deleting.
    - Page has a Map button - navigates to another page to show gpx trace on top
      of openstreetmap tile view (see later, section Mapping).

### Gps Collecting Data Format

- Collect gps trace points as
    - Time point for start of Recording = t-start
    - List of...
        - event type - Pause; Point; Unpause
        - Millisecond time point for this event - in milliseconds since t-start - event-type = {all}
        - gps coordinate (lat/long as per normal conventions) - event-type = Point
        - Accuracy of gps coordinate in meters - event-type = Point
- Each gps track_events collection should have a name (string) field allowing
  renaming.
- To save battery life, don't poll the gps event more than, say, once in every 10s
  please.

### Mapping

- Page navigates after selected a gpx trace and clicking Map button.
- Shows a view of the openstreetmap tiles that are just sufficient for all of
  the areas in the gpx trace.
- To start, use a zoom level - 15. The user can click a button to change
  this zoom level within a range (13..17 to start with).
- We will draw on top of the map tiles the gpx route we took.
    - See later on line style.
- Map view - not zoomable yet (except the zoom level changeable).
- As per earlier, we should cache the sqlite tiles to reduce load on osm.
  I want to track tiles loaded in our sqlite database (number of bytes loaded)
  along with information about reuse of caching (by bytes) so that I can be sure
  that caching is working. Show this in Debug page from Home page.
- The line style has some options that are selectable on the Map page.
    - Style 1 - Track line style - blue semi-transparent (40% opacity) line, 5 pixels wide,
    with a black (40% opacity) 7 pixel border underneath for visibility against map content.
    - Style 2 - as per Style 1 but green.
    - Style 3 - as per Style 1 but bright orange.
    - The options are saved into persistent storage so that it will have
      the last chosen option on returning to this page or after restart.

### Challenges

- The app, when collecting gps data, must continue collecting data from
  the lock screen or in background. Other resources have told me to
  look at these areas.
    - Use flutter_background_geolocation.
    - Add and request ACCESS_BACKGROUND_LOCATION and FOREGROUND_SERVICE
      permissions.
    - Run location tracking as a foreground service with a persistent
      notification.
    - Ask users to disable battery optimizations in the app.