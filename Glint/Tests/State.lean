/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Glint.Core
import Glint.Display
import Glint.Tests.Util

/-! # Times and runs

Lines saved with their times, and lines saved before glint kept times; the core stamping what
each step adds; times and dates shown; and a conversation cut into runs. -/

namespace Glint.Tests.StateTests

open Glint Glint.Tests
open CryptWalker.GroupChat.Member
open CryptWalker.GroupChat.Member.Persist
open CryptWalker.GroupChat.Member.Persist.Persist

def bob : Key := ByteArray.mk #[2]
def carol : Key := ByteArray.mk #[3]

def msg (id : Nat) (sender : Key) (min : Nat) : Line :=
  { id, sender, text := s!"m{id}", time := some (min * 60000) }

def tests : TestM Unit := do
  -- Saving.
  let l : Line := { id := 7, sender := bob, text := "hi", time := some 1792055520000 }
  let back : Option Line := ofTerm (toTerm l)
  check "a line saves and loads with its time" (back.any fun b => b.time == some 1792055520000 && b.text == "hi")
  let old := match toTerm l with
    | .TList fs => Cborg.Term.TList (fs.extract 0 6)
    | t => t
  let oldBack : Option Line := ofTerm old
  check "a line saved before times were kept loads, with none" (oldBack.any fun b => b.time.isNone && b.id == 7)
  let s : State := { me := "alice", chats := [{ name := "g", log := [l] }] }
  check "a state with times saves and loads" ((load (save s) : Option State).any fun b =>
    b.chats.any fun c => c.log.any (·.time == some 1792055520000))
  -- Stamping.
  let core : Core := { state := { me := "alice" }, now := 1000 }
  let (core, _) := step core (.create "g")
  -- A second group of that name is refused, with a notice: the line this step adds.
  let (core, _) := step { core with now := 2000 } (.create "g")
  check "what a step adds is stamped with the time now" ((core.state.chat? "g").any fun c =>
    c.log.length == 1 && c.log.all (·.time == some 2000))
  let (core, _) := step { core with now := 3000 } (.create "g")
  check "and what was there keeps its time" ((core.state.chat? "g").any fun c =>
    (c.log.map (·.time)) == [some 2000, some 3000])
  -- Showing times.
  checkEq "the time of day" "09:12" (Display.clock 0 1792055520000)
  checkEq "at an offset from UTC" "11:12" (Display.clock 7200 1792055520000)
  checkEq "midnight" "00:00" (Display.clock 0 0)
  checkEq "the epoch's date" "Jan 1" (Display.date 0)
  checkEq "a date this year" "Oct 15" (Display.date (Display.dayOf 0 1792055520000))
  checkEq "a leap day" "Feb 29" (Display.date (Display.dayOf 0 1709208000000))
  -- Runs.
  let notice : Line := { id := 9, text := "a notice", time := some 60000 }
  let runs := Display.runs [msg 0 bob 0, msg 1 bob 3, msg 2 carol 4, msg 3 carol 5, notice, msg 4 carol 6, msg 5 carol 20]
  let shape := runs.map fun
    | .messages s ls => s!"{if s == bob then "bob" else "carol"}{ls.map (fun (l : Line) => l.id)}"
    | .notice l => s!"notice{l.id}"
  checkEq "messages are cut into runs by sender, notices and five-minute gaps"
    ["bob[0, 1]", "carol[2, 3]", "notice9", "carol[4]", "carol[5]"] shape
  checkEq "a run's first line" (some 0) ((runs.head?.bind Display.Run.first).map (fun (l : Line) => l.id))

end Glint.Tests.StateTests
