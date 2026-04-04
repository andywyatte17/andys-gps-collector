import os, sys
import subprocess as sp
from os.path import join

# Add in a MacOS-ish location for Android sdk

os.environ["PATH"] += \
  os.pathsep + join( \
      os.path.expanduser("~"), "Library", "Android", \
        "sdk", "emulator")

avds = sp.check_output("emulator -list-avds", shell=True) \
    .decode('ascii') \
    .splitlines()

mapping = {}

for x, c in zip(avds, range(1, 1000)):
  mapping[c] = x
  print(f"\t{c}: {x}")

number = int(input("Which emulator to start? ").strip())
sp.check_call(f'emulator -avd "{mapping[number]}"', shell=True)
