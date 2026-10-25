/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import FrankChat.Tests.Display
import FrankChat.Tests.Command
import FrankChat.Tests.State
import FrankChat.Tests.App
import FrankChat.Tests.Shot
import FrankChat.Tests.Members
import FrankChat.Tests.Files
import FrankChat.Tests.Voice
import FrankChat.Tests.Phone

/-! # frank_chat's tests, in one process, with no daemon or window -/

open FrankChat.Tests

def main (args : List String) : IO UInt32 := do
  if let ["--shot", dir] := args then
    Shot.shots dir
    return 0
  if let ["--readme", path] := args then
    Shot.readme path
    return 0
  if let ["--fixture", dir] := args then
    Shot.fixture dir
    return 0
  let mut ok := true
  for (name, t) in [("display", DisplayTests.tests),
      ("command", CommandTests.tests), ("state", StateTests.tests), ("app", AppTests.tests), ("members", Members.tests),
      ("files", FilesTests.tests), ("voice", VoiceTests.tests), ("phone", PhoneTests.tests)] do
    ok := (← runSuite name t) && ok
  -- Tasks of the shells may still be asleep; they would keep the process alive.
  IO.Process.exit (if ok then 0 else 1)
