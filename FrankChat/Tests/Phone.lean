/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import FrankChat.Tests.Voice

/-! # A phone

The app in a phone's window, 411 wide: one pane at a time, the groups or a conversation, with
everything in reach inside the window. -/

namespace FrankChat.Tests.PhoneTests

open FrankChat FrankChat.Tests FrankChat.Tests.AppTests Paw
open GroupChatClient GroupChatClient.GroupChatKatzenqt1

variable {sent : Sent}

def has (r : Run sent true) (k : String) : Bool := (r.rt.tree.findKey? k).isSome

/-- Whether the widget keyed `k` is drawn, and wholly inside the window. -/
def inside (r : Run sent true) (k : String) : Bool :=
  match r.rt.tree.findKey? k with
  | some n => let v := n.viewport; let w := window true
    v.x0 < v.x1 && w.x0 ≤ v.x0 && v.x1 ≤ w.x1 && w.y0 ≤ v.y0 && v.y1 ≤ w.y1
  | none => false

def where_ (r : Run sent true) (k : String) : Unit → String := fun _ =>
  match r.rt.tree.findKey? k with
  | some n => s!"{k} at {repr n.viewport}"
  | none => s!"{k} is not drawn"

def panes : TestM Unit := do
  let sent ← IO.mkRef #[]
  let r := begin sent true
  check "with no groups, the empty state explains what to do" ((textsOf r "empty") == ["No groups yet"])
  check "and its buttons are in reach" (inside r "empty-new" && inside r "empty-join") (where_ r "empty-join")
  let r ← click r "empty-join"
  for k in ["dialog-field", "dialog-me", "accept", "cancel"] do
    check s!"Join's {k} is in reach" (inside r k) (where_ r k)
  let r ← key r .escape
  let r ← state r { me := "alice", chats := [chatWith "g" [], chatWith "h" []] }
  check "with groups, they are shown, none selected" (has r "groups" && r.rt.model.selected.isNone)
  check "and no conversation beside them" (!has r "conversation" && !has r "draft")
  check "the status bar stays at the bottom"
    ((r.rt.tree.findKey? "status").any fun n => decide (n.viewport.y1 > (window true).y1 - px 60)) (where_ r "status")
  let r ← click r "group:g"
  check "a click opens the group, alone" (r.rt.model.selected == some "g" && has r "conversation" && !has r "groups")
  for k in ["back", "title", "more", "draft", "talk", "attach", "send"] do
    check s!"{k} is in reach" (inside r k) (where_ r k)
  let r ← click r "draft"
  let r ← typeText r "hello"
  let r ← click r "send"
  check "Send posts the draft" ((← last sent) == some "g: send 5 characters")
  let r ← click r "back"
  check "Back shows the groups again" (r.rt.model.selected.isNone && has r "groups")
  let r ← click r "group:h"
  check "and the other group opens" (r.rt.model.selected == some "h")
  let r ← key r .escape
  check "Escape, the back key, shows the groups" (r.rt.model.selected.isNone && has r "groups")
  let r ← state r { me := "alice", chats := [chatWith "g" [line 0 "one"], chatWith "h" []] }
  check "a new state keeps them shown" r.rt.model.selected.isNone

def menu : TestM Unit := do
  let sent ← IO.mkRef #[]
  let r ← state (begin sent true) { me := "alice", chats := [chatWith "g" []] }
  let r ← click r "group:g"
  check "the group's actions are in a menu" (!has r "invite" && !has r "leave")
  let r ← click r "more"
  for k in ["invite", "remove", "scan", "rename", "clear", "leave"] do
    check s!"More shows {k}, in reach" (inside r k) (where_ r k)
  let r ← click r "invite"
  check "Invite opens its dialog and closes the menu"
    (r.rt.model.dialog.any (·.kind == .invite) && !r.rt.model.menu)
  let r ← key r .escape
  check "Escape closes the dialog and stays in the group"
    (r.rt.model.dialog.isNone && r.rt.model.selected == some "g")
  let long := "a group with a name much too long for a phone's narrow window"
  let r ← state r { me := "alice", chats := [chatWith long []] }
  let r ← click r s!"group:{long}"
  check "with a long name, More is still in reach" (inside r "more" && inside r "back") (where_ r "more")

def voice : TestM Unit := do
  VoiceTests.setup
  let sent ← IO.mkRef #[]
  let r ← state (begin sent true) { me := "alice", chats := [chatWith "g" []] }
  let r ← click r "group:g"
  let r ← input r (.press (at_ r "talk") .primary) 600
  let r ← input r (.release (at_ r "talk") .primary) 100
  check "a voice note recorded" (match r.rt.model.voice with | .draft .. => true | _ => false)
  for k in ["draft-play", "draft-discard", "draft-send"] do
    check s!"{k} is in reach" (inside r k) (where_ r k)

def tests : TestM Unit := do
  panes
  menu
  voice

end FrankChat.Tests.PhoneTests
