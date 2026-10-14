/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Linux
import Glint.Tests.App

/-! # Pictures of the window

The window drawn offscreen with the bundled fonts, for a person to look at. -/

namespace Glint.Tests.Shot

open Glint Glint.Tests Paw

def write {caps : List Cap} {app : Paw.App caps} (rt : Runtime app) (path : System.FilePath) : IO Unit := do
  let scene := match rt.present with | .request (.present s) => s | _ => Scene.empty
  IO.FS.writeBinFile path (Linux.renderPng scene 1000 700)

def shots (dir : System.FilePath) : IO Unit := do
  IO.FS.createDirAll dir
  let sent ← IO.mkRef #[]
  let some c ← DisplayTests.threeMembers | throw (IO.userError "no group")
  let bob := (c.names.pairs.find? (·.2 == "bob")).map (·.1) |>.getD .empty
  let me := (c.group.map (·.me)).getD .empty
  let c := { c with log := [AppTests.line 0 "~alice added ~bob", AppTests.line 1 "hello alice" bob,
    AppTests.line 2 "a message\nof two lines" bob, AppTests.line 3 "hi bob" me .pending, AppTests.line 4 "sent" me] }
  let start := (Paw.Runtime.start (AppTests.mkApp sent) (Rect.ofXYWH 0 0 (px 1000) (px 700)) 0 Linux.measure (motion := false)).1
  write start (dir / "empty.png")
  let (rt, _) := start.results [App.Msg.state { me := "alice", chats := [c, { name := "other" }] }] 100
  write rt (dir / "chat.png")
  let joining : Chat := { name := "theirs", joining := some (.awaiting "SGVsbG8gdm91Y2hlciBjb2RlIHRoYXQgaXMgcXVpdGUgbG9uZyBpbmRlZWQ=" .empty .empty .empty) }
  let (rt, _) := start.results [App.Msg.state { me := "alice", chats := [joining] }] 100
  write rt (dir / "joining.png")

/-- A saved state for the end-to-end tests: Alice in a group of three, and a second group. -/
def fixture (dir : System.FilePath) : IO Unit := do
  IO.FS.createDirAll dir
  let some c ← DisplayTests.threeMembers | throw (IO.userError "no group")
  let bob := (c.names.pairs.find? (·.2 == "bob")).map (·.1) |>.getD .empty
  let c := { c with log := [AppTests.line 0 "~alice added ~bob", AppTests.line 1 "hello alice" bob] }
  let s : State := { me := "alice", chats := [c, AppTests.chatWith "second" [AppTests.line 0 "a notice"]] }
  IO.FS.writeBinFile (dir / "state.cbor") (CryptWalker.GroupChat.Member.Persist.save s)

end Glint.Tests.Shot
