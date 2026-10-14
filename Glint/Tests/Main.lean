/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Glint.Tests.Core
import Glint.Tests.Display
import Glint.Tests.Command
import Glint.Tests.App
import Glint.Tests.Shot

/-! # glint's tests, in one process, with no daemon or window -/

open Glint.Tests

def main (args : List String) : IO UInt32 := do
  if let ["--shot", dir] := args then
    Shot.shots dir
    return 0
  if let ["--fixture", dir] := args then
    Shot.fixture dir
    return 0
  let mut ok := true
  for (name, t) in [("core", CoreTests.tests), ("display", DisplayTests.tests),
      ("command", CommandTests.tests), ("app", AppTests.tests)] do
    ok := (← runSuite name t) && ok
  return if ok then 0 else 1
