/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw
import Glint.Command
import Glint.Display

/-! # The window

The groups on the left, the selected conversation in the middle, and on the right everyone who
reads what is written there, each with the start of their key. Below, the log, which F2 hides, and
a status row.

glint, not the sender, decides what each part of the window says:

- Text from elsewhere reaches a widget only through `Glint.Display`.
- A member is named `me` or `~name`; a name that could be taken for another's also shows the start
  of its key. Delivery marks sit in a column of their own, and a name cannot hold them.
- A message is drawn to the right of the sender column, all its rows, so it cannot pass for the
  next one; glint's own notices are drawn in a panel no message has.
- The message box only sends text. Everything else is a button, and what uses authority (a dialog,
  copying) happens only for the user's own click. The window's title is always "glint". -/

namespace Glint.App

open Paw
open CryptWalker.GroupChat.Member

abbrev caps : List Cap := [.clipboardWrite, .io]

inductive DialogKind
  | newGroup
  | join
  | invite
  | remove
  | leave
  | clear
  deriving BEq, Repr, Inhabited

structure Dialog where
  kind : DialogKind
  modal : Modal
  /-- The group it is about. -/
  chat : Option String := none
  field : String := ""
  /-- The member chosen, by the hex of their key. -/
  pick : Option String := none
  note : String := ""
  deriving BEq

inductive Msg
  /-- The core's state, from the shell. -/
  | state (s : State)
  | logs (lines : Array String)
  | select (chat : String)
  | draft (s : String)
  | send
  | scan
  | ask (d : DialogKind)
  | field (s : String)
  | pick (key : String)
  | confirm
  | dismiss
  | copyVoucher
  | toggleLog
  | toggleBlank
  /-- The share of the groups pane, or of the conversation beside the members. -/
  | ratio (outer : Bool) (n : Nat)
  | next (forward : Bool)
  | quit
  /-- A message reached the core. -/
  | posted

structure Model where
  state : State
  /-- How many states have arrived, so that a new one is a change. -/
  version : Nat := 0
  selected : Option String := none
  /-- Lines of each conversation seen, for unread counts. -/
  seen : List (String × Nat) := []
  logs : Array String := #[]
  showLog : Bool := true
  /-- The window blanked, for someone looking over your shoulder. -/
  blank : Bool := false
  draft : String := ""
  note : String := ""
  /-- A group asked for, to select once it appears. -/
  want : Option String := none
  dialog : Option Dialog := none
  outer : Nat := 220
  inner : Nat := 760
  /-- What glint is connected to. -/
  network : String := ""
  deriving Inhabited

instance : BEq Model where
  beq a b := a.version == b.version && a.selected == b.selected && a.seen == b.seen &&
    a.logs == b.logs && a.showLog == b.showLog && a.blank == b.blank && a.draft == b.draft &&
    a.note == b.note && a.want == b.want && a.dialog == b.dialog && a.outer == b.outer &&
    a.inner == b.inner && a.network == b.network

namespace Model

def current (m : Model) : Option Chat := m.selected.bind m.state.chat?

/-- Count the selected conversation as read. -/
def markSeen (m : Model) : Model :=
  match m.current with
  | some c => { m with seen := (c.name, c.log.length) :: m.seen.filter (·.1 != c.name) }
  | none => m

/-- Take a new state: keep the selection while its group exists, and select a group asked for
once it appears. -/
def take (m : Model) (s : State) : Model :=
  let has (n : String) := s.chats.any (·.name == n)
  let selected := match m.want with
    | some w => if has w then some w else m.selected
    | none => m.selected
  let selected := (selected.filter has).orElse fun _ => s.chats.head?.map (·.name)
  markSeen { m with state := s, version := m.version + 1, selected,
                    want := m.want.filter (!has ·) }

def voucher? (c : Chat) : Option String :=
  match c.joining with
  | some (.awaiting code ..) => some code
  | _ => none

/-- The member of the selected group whose key is `hex`. -/
def memberByHex (m : Model) (hex : String) : Option CryptWalker.GroupChat.Member.Key :=
  (m.current.bind (·.group)).bind fun g => g.readers.keys.find? (Display.hex · == hex)

end Model

/-- What the core is asked, and glint's note on it; the message goes to the core on a task. -/
def perform {o : Origin} (post : Glint.Msg → IO Unit) (a : Command.Asked) :
    UpdateM Model Msg caps o Unit := do
  modify fun (m, cs) => ({ m with note := a.note, want := a.want.orElse fun _ => m.want }, cs)
  if let some msg := a.msg then emit (.task (do post msg; pure .posted) (by decide))

/-- What the open dialog asks for, when confirmed. -/
def confirmed (m : Model) (d : Dialog) : Command.Asked :=
  match d.kind with
  | .newGroup => Command.newGroup m.state d.field
  | .join => Command.joinGroup m.state d.field
  | .invite => Command.invite d.chat d.field
  | .leave => Command.leave d.chat d.field
  | .clear => Command.clear d.chat
  | .remove => match d.pick.bind m.memberByHex with
    | some k => Command.remove m.state d.chat k
    | none => { note := "choose a member first" }

def needsGroup : DialogKind → Bool
  | .newGroup | .join => false
  | _ => true

def update (post : Glint.Msg → IO Unit) : (o : Origin) → Msg → UpdateM Model Msg caps o Unit
  | _, .state s => modify fun (m, cs) => (m.take s, cs)
  | _, .logs lines => modify fun (m, cs) => ({ m with logs := lines }, cs)
  | _, .select chat => modify fun (m, cs) =>
    if m.state.chats.any (·.name == chat) then ((({ m with selected := some chat } : Model)).markSeen, cs)
    else (m, cs)
  | _, .next forward => modify fun (m, cs) =>
    let names := m.state.chats.map (·.name)
    let n := names.length
    if n == 0 then (m, cs) else
    let i := ((m.selected.bind fun s => names.idxOf? s)).getD 0
    let j := if forward then (i + 1) % n else (i + n - 1) % n
    ((({ m with selected := names[j]? } : Model)).markSeen, cs)
  | _, .draft s => modify fun (m, cs) => ({ m with draft := s }, cs)
  | _, .send => do
    let m := (← get).1
    let a := Command.send m.selected m.draft
    if a.msg.isSome then modify fun (m, cs) => ({ m with draft := "" }, cs)
    perform post a
  | _, .scan => do perform post (Command.scan (← get).1.selected)
  | .user d, .ask kind => modify fun (m, cs) =>
    if needsGroup kind && m.current.isNone then ({ m with note := "select a group first" }, cs)
    else ({ m with dialog := some { kind, modal := Modal.open d, chat := m.selected } }, cs)
  | .other, .ask _ => pure ()
  | _, .field s => modify fun (m, cs) => ({ m with dialog := m.dialog.map ({ · with field := s }) }, cs)
  | _, .pick k => modify fun (m, cs) => ({ m with dialog := m.dialog.map ({ · with pick := some k }) }, cs)
  | _, .confirm => do
    let m := (← get).1
    let some d := m.dialog | return
    let a := confirmed m d
    if a.msg.isNone then
      modify fun (m, cs) => ({ m with dialog := some { d with note := a.note } }, cs)
    else
      modify fun (m, cs) => ({ m with dialog := none }, cs)
      perform post a
  | _, .dismiss => modify fun (m, cs) => ({ m with dialog := none }, cs)
  | .user d, .copyVoucher => do
    let some code := (← get).1.current.bind Model.voucher? | return
    let e := Effect.setClipboard "copy-voucher" (SafeText.filter code)
    if h : e.DesignatedBy d then emit (.effect d e (by decide) h)
  | .other, .copyVoucher => pure ()
  | _, .toggleLog => modify fun (m, cs) => ({ m with showLog := !m.showLog }, cs)
  | _, .toggleBlank => modify fun (m, cs) => ({ m with blank := !m.blank }, cs)
  | _, .ratio outer n => modify fun (m, cs) =>
    let n := max 100 (min 900 n)
    (if outer then { m with outer := n } else { m with inner := n }, cs)
  | _, .quit => emit .quit
  | _, .posted => pure ()

/-! ## The view -/

/-- What a conversation row is drawn from, so that a row that did not change is not built again. -/
structure Row where
  notice : Bool
  who : SafeText
  lines : List SafeText
  /-- `…` pending, `✓` written, `✓✓` acknowledged; empty for another's message. -/
  mark : String
  deriving BEq, TypeName

def rowOf (me : String) (c : Chat) (l : Line) : Row :=
  if l.sender.size == 0 then { notice := true, who := SafeText.empty, lines := Display.body l.text, mark := "" }
  else
    let mine := c.group.any (·.me == l.sender)
    let mark := if !mine then "" else match l.status with
      | .pending => "…"
      | .sent => if acknowledged c l then "✓✓" else "✓"
    { notice := false, who := Display.who me c l.sender, lines := Display.body l.text, mark }

def senderWidth : Int := px 150

def rowView (r : Row) : Node Msg :=
  let body := Ui.col (spacing := 0) (r.lines.map fun t => Ui.text t (maxLines := 40))
  if r.notice then
    Ui.panel (Ui.row [Ui.label "—", body] (px 6)) (px 4)
  else
    Ui.row [Ui.width senderWidth (Ui.text r.who (overflow := .ellipsis)),
      Ui.width (px 24) (Ui.label r.mark), body] (px 6)

def groupsPane (m : Model) : Node Msg :=
  let names := m.state.chats.map (·.name)
  let caption (n : String) := ((m.state.chat? n).map (Display.groupRow m.seen)).getD n
  Ui.pad (px 6) <| Ui.col [
    Ui.label "Groups",
    Ui.selectList names m.selected .select caption ("group:" ++ ·) (rows := 14) (key := "groups"),
    Ui.button "New group" (.ask .newGroup) "new-group",
    Ui.button "Join a group" (.ask .join) "join-group"] (px 6)

def empty : Node Msg :=
  Ui.pad (px 12) <| Ui.col [
    Ui.label "No groups yet." (key := "empty"),
    Ui.label "New group starts a group of your own." (maxLines := 3),
    Ui.label ("To join someone else's group, choose Join a group: a voucher code appears, which " ++
      "you give to one of its members, who adds you with Invite.") (maxLines := 4)] (px 8)

def sendCaption (c : Chat) (draft : String) : String :=
  let n := (draft.splitOn "\n").length
  let to := (Display.name c.name).text
  if n > 1 then s!"Send {n} lines to {to}" else s!"Send to {to}"

def conversationPane (m : Model) (c : Chat) : Node Msg :=
  let me := m.state.me
  let info := match c.group with
    | some g => s!"epoch {g.epoch} · {c.jobs.length} to write"
    | none => if c.joining.isSome then "joining" else "starting"
  let joined := c.group.isSome
  let header := Ui.col [
    Ui.row [Ui.text (Display.name c.name).toText (overflow := .ellipsis) (key := "title"),
      Ui.label info "info"] (px 8),
    Ui.row [
      Ui.enabled joined (Ui.button "Invite" (.ask .invite) "invite"),
      Ui.enabled joined (Ui.button "Remove member" (.ask .remove) "remove"),
      Ui.button "Clear" (.ask .clear) "clear",
      Ui.enabled joined (Ui.button "Scan" .scan "scan"),
      Ui.button "Leave" (.ask .leave) "leave"] (px 6)] (px 6)
  let voucher := (Model.voucher? c).toList.map fun code =>
    Ui.panel (Ui.col [
      Ui.label "Your voucher code: give it to a member of the group, who adds you with Invite." (maxLines := 2),
      Ui.row [Ui.text (Display.text code) (maxLines := 6) (key := "voucher-code"),
        Ui.button "Copy" .copyVoucher "copy-voucher"] (px 6)] (px 6))
  let lines := Ui.scroll (Ui.list c.log (fun l => s!"line:{l.id}") fun l =>
      Ui.lazy (rowOf me c l) rowView) "conversation" (follow := true)
  let input := Ui.height (px 84) <| Ui.row [
    Ui.keystroke [({ key := .enter, ctrl := true }, .send)]
      (Ui.textArea m.draft .draft { rows := 3, placeholder := SafeText.trusted "a message" } "draft"),
    Ui.enabled joined (Ui.button (sendCaption c m.draft) .send "send")] (px 6)
  Ui.pad (px 6) <| Ui.col ([header] ++ voucher ++ [lines, input]) (px 6)

def membersPane (m : Model) (c : Chat) : Node Msg :=
  let row (mb : Display.Member) : Node Msg :=
    Ui.text (mb.label ++ SafeText.trusted s!" {Display.fingerprint mb.key}{if mb.doubtful then " (!)" else ""}")
      (overflow := .ellipsis)
  Ui.pad (px 6) <| Ui.col [Ui.label "Members",
    Ui.list (Display.members m.state.me c) (fun mb => s!"member:{Display.hex mb.key}") row (px 2)] (px 6)

def logPane (m : Model) : Node Msg :=
  Ui.height (px 120) <| Ui.pad (px 6) <| Ui.scroll (Ui.col (spacing := 0)
    (m.logs.toList.map fun l => Ui.text (Display.text l))) "log" (follow := true)

def status (m : Model) : String :=
  let pending := m.state.chats.foldl (fun n c => n + c.jobs.length) 0
  let epoch := match m.current.bind (·.group) with
    | some g => s!"epoch {g.epoch} · "
    | none => ""
  s!"{epoch}{pending} to write · {m.network}{if m.note.isEmpty then "" else " · " ++ m.note}"

def accept (caption : String) : Node Msg :=
  Node.leaf (Widgets.button (SafeText.trusted caption) .confirm (designated := true)) "accept"

def dialogView (m : Model) (d : Dialog) : Node Msg :=
  let group := (Display.name (d.chat.getD "")).text
  let field (placeholder : String) :=
    Ui.textField d.field .field { placeholder := SafeText.trusted placeholder } "dialog-field"
  let buttons (caption : String) := Ui.row [Ui.spacer, Ui.button "Cancel" .dismiss "cancel", accept caption]
  let note := if d.note.isEmpty then [] else [Ui.text (Display.text d.note) (maxLines := 3) (key := "dialog-note")]
  let body (title : String) (parts : List (Node Msg)) (caption : String) :=
    Ui.dialog d.modal (SafeName.filter title)
      (Ui.width (px 420) (Ui.col ([Node.leaf (Widgets.label (SafeText.trusted title) (bold := true))] ++
        parts ++ note ++ [buttons caption]) (px 8))) .dismiss
  match d.kind with
  | .newGroup => body "New group"
      [Ui.paragraph "A group of your own; you add members with Invite.", field "its name"] "Create"
  | .join => body "Join a group"
      [Ui.paragraph ("Name it as you will know it here. A voucher code will appear: give it to a " ++
        "member of the group, who adds you with Invite."), field "its name here"] "Join"
  | .invite => body s!"Invite to {group}"
      [Ui.paragraph s!"Whoever holds this code will read everything said in {group} from now on.",
        field "voucher code"] "Invite"
  | .remove =>
    let others := ((m.state.chat? (d.chat.getD "")).map (Display.members m.state.me ·)).getD [] |>.drop 1
    let hexes := others.map (Display.hex ·.key)
    let label (h : String) := ((others.find? (Display.hex ·.key == h)).map fun mb =>
      mb.label.text ++ s!" {Display.fingerprint mb.key}").getD h
    let chosen := (d.pick.map label).getD "The member you choose"
    body s!"Remove a member of {group}"
      [Ui.selectList hexes d.pick .pick label ("pick:" ++ ·) (rows := 6) (key := "members"),
        Ui.paragraph s!"{chosen} will no longer be read here; what they sent is deleted here. They can still read {group}."]
      "Remove"
  | .leave => body s!"Leave {group}"
      [Ui.paragraph s!"Leave {group} and delete it here? This cannot be undone. Type its name to confirm.",
        field "the group's name"] "Leave"
  | .clear => body s!"Clear {group}"
      [Ui.paragraph s!"Delete this conversation's lines here? The other members keep theirs."] "Clear"

def bindings : List (Widgets.KeyCombo × Msg) :=
  [({ key := .char 'q', ctrl := true }, .quit), ({ key := .f 10 }, .toggleBlank),
   ({ key := .f 2 }, .toggleLog), ({ key := .pageDown, ctrl := true }, .next true),
   ({ key := .pageUp, ctrl := true }, .next false)]

def view (m : Model) : Node Msg :=
  Ui.keystroke bindings <|
  if m.blank then Ui.pad (px 24) (Ui.label "glint · F10 to return" "blank") else
  let (middle, right) := match m.current with
    | some c => (conversationPane m c, membersPane m c)
    | none => (empty, Ui.spacer)
  let panes := Ui.split (groupsPane m) (Ui.split middle right m.inner (.ratio false) (key := "inner"))
    m.outer (.ratio true) (key := "outer")
  Ui.col ([panes] ++ (if m.showLog then [Ui.separator, logPane m] else []) ++
    [Ui.pad (px 6) (Ui.text (Display.text (status m)) (overflow := .ellipsis) (key := "status"))] ++
    (m.dialog.toList.map (dialogView m))) (px 4)

def app (post : Glint.Msg → IO Unit) (init : Model) (start : List (Cmd Msg caps .other) := []) :
    App caps :=
  { Model := Model, Msg := Msg, init, update := update post, view, start }

end Glint.App
