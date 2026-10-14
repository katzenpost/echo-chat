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

/-- Alice, Bob and Carol in a group over the simulated Pigeonhole, after a short conversation:
Alice's state, with her last message still on its way. -/
def conversation : IO (Option Chat) := do
  let world ← IO.mkRef ({} : Sim.World)
  let net : Net := { cores := #["alice", "bob", "carol"].map fun me => { state := { me } } }
  let say (who : Nat) (text : String) : NetM Bool := do
    feed who (.send "friends" text)
    runUntil world fun n => [0, 1, 2].all (says n · "friends" text)
  let (ok, net) ← (do
    feed 0 (.create "friends")
    for who in [1, 2] do
      feed who (.join "friends")
      unless ← runUntil world fun n => (code? n who "friends").isSome do return false
      let some code := code? (← get) who "friends" | return false
      feed 0 (.induct "friends" code)
      unless ← runUntil world fun n => joined n who "friends" &&
          !(chatOf n 0 "friends").any (fun (c : Chat) => c.inducting.isSome) do
        return false
    let mut ok := true
    for (who, text) in [(1, "Did everyone get the notes from Thursday?"),
        (2, "Yes. The second half was a lot to take in.\nI'll write up a summary tonight."),
        (0, "Got them, thanks. Coffee on Saturday to go through it?"),
        (1, "Saturday works for me."), (2, "Same. 10 at the usual place?")] do
      ok := ok && (← say who text)
    feed 0 (.send "friends" "10 it is, see you there")
    return ok).run net
  if !ok then return none
  return chatOf net 0 "friends"

/-- The picture in the README: Alice's window, in the dark theme, with three groups, one of them a conversation. -/
def readme (path : System.FilePath) : IO Unit := do
  let some friends ← conversation | throw (IO.userError "the conversation did not finish")
  let friends := { friends with log := friends.log.filter fun l =>
    !(l.text.startsWith "a new group" || l.text.startsWith "reading the voucher") }
  let work := AppTests.chatWith "work" [AppTests.line 0 "a new group: Invite, with a member's voucher code, adds them",
    AppTests.line 1 "added ~dana: they now read everything said in this group",
    AppTests.line 2 "added ~eli: they now read everything said in this group"]
  let book : Chat := { name := "book club", joining := some (.awaiting "" .empty .empty .empty) }
  let app := App.app (fun _ => pure ()) { state := { me := "alice" }, network := "daemon @katzenpost" }
  let rt := (Paw.Runtime.start app (Rect.ofXYWH 0 0 (px 1000) (px 640)) 0 Linux.measure (motion := false) (theme := Theme.dark)).1
  let logs := #["18:20:29.973 NOTI glint: started as alice", "18:21:02.114 INFO glint/net: friends: read box 41: 212 bytes",
    "18:21:15.611 INFO glint/driver: replica epoch 488", "18:21:40.020 INFO glint/net: friends: wrote job 7 at box 12"]
  let (rt, _) := rt.results [App.Msg.state { me := "alice", chats := [friends, work, book] }, .logs logs] 100
  let scene := match rt.present with | .request (.present s) => s | _ => Scene.empty
  IO.FS.writeBinFile path (Linux.renderPng scene 2000 1280 2000)

/-- A saved state for the end-to-end tests: Alice in a group of three, and a second group. -/
def fixture (dir : System.FilePath) : IO Unit := do
  IO.FS.createDirAll dir
  let some c ← DisplayTests.threeMembers | throw (IO.userError "no group")
  let bob := (c.names.pairs.find? (·.2 == "bob")).map (·.1) |>.getD .empty
  let c := { c with log := [AppTests.line 0 "~alice added ~bob", AppTests.line 1 "hello alice" bob] }
  let s : State := { me := "alice", chats := [c, AppTests.chatWith "second" [AppTests.line 0 "a notice"]] }
  IO.FS.writeBinFile (dir / "state.cbor") (CryptWalker.GroupChat.Member.Persist.save s)

end Glint.Tests.Shot
