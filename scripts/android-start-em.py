import argparse
import os
import subprocess as sp
import time
from os.path import join

parser = argparse.ArgumentParser(description="Start an Android emulator")
parser.add_argument(
    "-c", "--clear-before-starting",
    action="store_true",
    help="Wipe emulator user data (storage, accounts, apps) before starting",
)
args = parser.parse_args()

# Add in a MacOS-ish location for Android sdk

sdk_root = join(os.path.expanduser("~"), "Library", "Android", "sdk")
os.environ["PATH"] += os.pathsep + join(sdk_root, "emulator")
os.environ["PATH"] += os.pathsep + join(sdk_root, "platform-tools")

avds = sp.check_output("emulator -list-avds", shell=True) \
    .decode('ascii') \
    .splitlines()

mapping = {}

for x, c in zip(avds, range(1, 1000)):
  mapping[c] = x
  print(f"\t{c}: {x}")

number = int(input("Which emulator to start? ").strip())
avd_name = mapping[number]

if args.clear_before_starting:
  # Shut down any running emulator for this AVD before wiping.
  print(f"Shutting down running emulators before wipe...")
  sp.run("adb emu kill", shell=True, capture_output=True)
  time.sleep(3)

cmd = f'emulator -avd "{avd_name}"'
if args.clear_before_starting:
  cmd += " -wipe-data"
sp.check_call(cmd, shell=True)
