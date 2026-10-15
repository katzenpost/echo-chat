/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw
import Glint.Command
import Glint.Display

/-! # The window

The groups on the left, the selected conversation in the middle, and on the right everyone who
reads what is written there, each with the start of their key. Below, a status row, and the log
when F2 shows it.

glint, not the sender, decides what each part of the window says:

- Text from elsewhere reaches a widget only through `Glint.Display`.
- A member is named `me` or `~name`; a name that could be taken for another's also shows the start
  of its key. Delivery marks sit in a column of their own, and a name cannot hold them.
- A run of messages begins with a header glint draws, the sender in bold and flush left; every row
  of a message is indented under it in regular weight, so none can pass for a header. glint's own
  notices are small, muted and centered, as no message is.
- The message box only sends text. Everything else is a button, and what uses authority (a dialog,
  copying) happens only for the user's own click. The window's title is always "glint". -/

namespace Glint.App

open Paw
open GroupChatClient GroupChatClient.GroupChatKatzenqt1
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
  showLog : Bool := false
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
  /-- The dark theme, glint's own default; the light one only when asked for. -/
  dark : Bool := true
  /-- The local time zone, in seconds from UTC, for showing when lines were said. -/
  zone : Int := 0
  deriving Inhabited

instance : BEq Model where
  beq a b := a.version == b.version && a.selected == b.selected && a.seen == b.seen &&
    a.logs == b.logs && a.showLog == b.showLog && a.blank == b.blank && a.draft == b.draft &&
    a.note == b.note && a.want == b.want && a.dialog == b.dialog && a.outer == b.outer &&
    a.inner == b.inner && a.network == b.network && a.dark == b.dark && a.zone == b.zone

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
def perform {o : Origin} (post : GroupChatKatzenqt1.Msg → IO Unit) (a : Command.Asked) :
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

def update (post : GroupChatKatzenqt1.Msg → IO Unit) : (o : Origin) → Msg → UpdateM Model Msg caps o Unit
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

/-! ## The view

Spacing follows GNOME's steps of 6, 12 and 18 pixels: 6 within a group of controls, 12 between
things and around a pane, 18 between groups. -/

/-- Our mark on a line of ours: `…` until written, `✓` once written, `✓✓` once a member has
acknowledged it; nothing on another's. -/
def markOf (c : Chat) (l : Line) : String :=
  if !c.group.any (·.me == l.sender) then "" else match l.status with
    | .pending => "…"
    | .sent => if acknowledged c l then "✓✓" else "✓"

/-- A message as drawn: its lines and our mark, so that one that did not change is not built
again. -/
structure MessageRow where
  lines : List SafeText
  mark : String
  deriving BEq, TypeName

/-- Every row of a message is indented under its run's header and to the left of its mark, so no
row of it can pass for a header, which is bold and flush, or for a notice, which is centered. -/
def messageView (r : MessageRow) : Node Msg :=
  Ui.row [Ui.width (px 12) Ui.spacer,
    Ui.col (spacing := 0) (r.lines.map fun t => Ui.text t (maxLines := 40)), Ui.spacer,
    Ui.width (px 24) (Ui.caption (SafeText.trusted r.mark))] (px 6)

/-- A notice of glint's as drawn. -/
structure NoticeRow where
  lines : List SafeText
  deriving BEq, TypeName

/-- glint's own notice: small and muted, centered, as no message is. -/
def noticeView (r : NoticeRow) : Node Msg :=
  Ui.row [Ui.spacer, Ui.col (spacing := 0) (r.lines.map fun t =>
    Ui.text t (maxLines := 4) (tone := .muted) (size := .caption)), Ui.spacer]

/-- Who said a run of messages, bold, and when, muted. -/
def headerView (who : SafeText) (time : String) : Node Msg :=
  Ui.row [Ui.text who (overflow := .ellipsis) (bold := true), Ui.caption (SafeText.trusted time)] (px 6)

/-- A line between regions, a pixel thick. -/
def rule : Node Msg := Ui.height (px 1) Ui.separator

def timeOf (m : Model) (l : Line) : String := (l.time.map (Display.clock m.zone)).getD ""

/-- A conversation as runs: each run of one sender's messages under one header, glint's notices
alone, and a date between runs of different days. -/
def conversation (m : Model) (c : Chat) : Node Msg :=
  let me := m.state.me
  let runs := Display.runs c.log
  let (_, items) := runs.foldl (fun (acc : Option Int × List (Node Msg)) run =>
    let (day, items) := acc
    let first := run.first
    let thisDay := (first.bind (·.time)).map (Display.dayOf m.zone)
    let dated := match thisDay, day with
      | some d, some p => if d != p then [Ui.row [Ui.spacer, Ui.caption (SafeText.trusted (Display.date d)) s!"day:{d}", Ui.spacer]] else []
      | _, _ => []
    let node := match run with
      | .notice l => Ui.lazy ({ lines := Display.body l.text } : NoticeRow) noticeView (key := some s!"line:{l.id}")
      | .messages sender ls =>
        let head := headerView (Display.who me c sender) ((ls.head?.map (timeOf m)).getD "")
        Ui.col (spacing := px 2) (head :: ls.map fun l =>
          Ui.lazy ({ lines := Display.body l.text, mark := markOf c l } : MessageRow) messageView
            (key := some s!"line:{l.id}")) (key := s!"run:{(ls.head?.map (·.id)).getD 0}")
    (thisDay.orElse fun _ => day, items ++ dated ++ [node])) (none, [])
  Ui.scroll (Ui.pad (px 12) (Ui.col items (px 12))) "conversation" (follow := true)

def groupRowView (m : Model) (c : Chat) : Node Msg :=
  let n := Display.unread m.seen c
  let state := if c.joining.isSome then "joining…" else if c.inducting.isSome then "adding…"
    else if c.group.isNone then "starting…" else ""
  Ui.row ([Ui.text (Display.name c.name).toText (overflow := .ellipsis) (bold := n > 0)] ++
    (if state.isEmpty then [] else [Ui.caption (SafeText.trusted state)]) ++ [Ui.spacer] ++
    (if n > 0 then [Ui.badge n] else [])) (px 6)

def groupsPane (m : Model) : Node Msg :=
  let names := m.state.chats.map (·.name)
  let row (n : String) := ((m.state.chat? n).map (groupRowView m)).getD (Ui.label n)
  Ui.surface <| Ui.pad (px 12) <| Ui.col [
    Ui.row [Ui.heading "Groups", Ui.spacer, Ui.flatButton "New" (.ask .newGroup) "new-group",
      Ui.flatButton "Join" (.ask .join) "join-group"] (px 6),
    Ui.selectListOf names m.selected .select row (fun n => (Display.name n).text) ("group:" ++ ·)
      (rows := 14) (framed := false) (key := "groups")] (px 12)

/-- With no group yet: what to do, centered. -/
def empty : Node Msg :=
  Ui.col [Ui.filler, Ui.row [Ui.spacer, Ui.width (px 380) (Ui.col [
    Ui.label "No groups yet" "empty" (bold := true) (size := .title),
    Ui.label ("Start a group of your own, or join someone else's: a voucher code appears, which " ++
      "you give to one of its members, who adds you with Invite.") (maxLines := 4) (tone := .muted),
    Ui.row [Ui.mainButton "New group" (.ask .newGroup) "empty-new",
      Ui.button "Join a group" (.ask .join) "empty-join"] (px 6)] (px 12)), Ui.spacer], Ui.filler] 0

def sendCaption (c : Chat) (draft : String) : String :=
  let n := (draft.splitOn "\n").length
  let to := (Display.name c.name).text
  if n > 1 then s!"Send {n} lines to {to}" else s!"Send to {to}"

def conversationPane (m : Model) (c : Chat) : Node Msg :=
  let info := match c.group with
    | some g => s!"{g.readers.size + 1} members · epoch {g.epoch}"
    | none => if c.joining.isSome then "waiting to be added" else "starting"
  let joined := c.group.isSome
  let header := Ui.pad (px 12) <| Ui.row [
    Ui.col [Ui.text (Display.name c.name).toText (key := "title") (overflow := .ellipsis) (bold := true)
        (size := .heading), Ui.caption (SafeText.trusted info) "info"] (px 2),
    Ui.spacer,
    Ui.enabled joined (Ui.flatButton "Invite" (.ask .invite) "invite"),
    Ui.enabled joined (Ui.flatButton "Remove" (.ask .remove) "remove"),
    Ui.enabled joined (Ui.flatButton "Scan" .scan "scan"),
    Ui.width (px 12) Ui.spacer,
    Ui.flatButton "Clear" (.ask .clear) "clear",
    Ui.destructiveButton "Leave" (.ask .leave) "leave"] (px 6)
  let voucher := (Model.voucher? c).toList.map fun code =>
    Ui.pad (px 12) <| Ui.panel (Ui.col [
      Ui.heading "Your voucher code",
      Ui.label "Give it to a member of the group, who adds you with Invite. It is also in the state directory."
        (maxLines := 3) (tone := .muted),
      Ui.row [Ui.text (Display.text code) (maxLines := 6) (key := "voucher-code"), Ui.spacer,
        Ui.mainButton "Copy" .copyVoucher "copy-voucher"] (px 12)] (px 6))
  let composer := Ui.pad (px 12) <| Ui.height (px 72) <| Ui.row [
    Ui.keystroke [({ key := .enter, ctrl := true }, .send)]
      (Ui.textArea m.draft .draft { rows := 3, placeholder := SafeText.trusted "a message" } "draft"),
    Node.container (box { alignV := .bottom })
      [Ui.enabled joined (Ui.mainButton (sendCaption c m.draft) .send "send")]] (px 12)
  Ui.col ([header, rule] ++ voucher ++ [conversation m c, rule, composer]) 0

def membersPane (m : Model) (c : Chat) : Node Msg :=
  let ms := Display.members m.state.me c
  let row (mb : Display.Member) : Node Msg :=
    Ui.row ([Ui.text mb.label (overflow := .ellipsis)] ++
      (if mb.doubtful then [Ui.tooltip ("This name could be taken for another's, or for yours, or it mixes " ++
          "scripts: tell them apart by the start of their key.") (Ui.label "(!)" (tone := .error))] else []) ++
      [Ui.spacer, Ui.caption (SafeText.trusted (Display.fingerprint mb.key))]) (px 6)
  Ui.surface <| Ui.pad (px 12) <| Ui.col [
    Ui.row [Ui.heading "Members", Ui.caption (SafeText.trusted (toString ms.length))] (px 6),
    Ui.list ms (fun mb => s!"member:{Display.hex mb.key}") row (px 6)] (px 12)

def logPane (m : Model) : Node Msg :=
  Ui.height (px 120) <| Ui.pad (px 6) <| Ui.scroll (Ui.col (spacing := 0)
    (m.logs.toList.map fun l => Ui.caption (Display.text l) (overflow := .clip))) "log" (follow := true)

def status (m : Model) : String :=
  let pending := m.state.chats.foldl (fun n c => n + c.jobs.length) 0
  let epoch := match m.current.bind (·.group) with
    | some g => s!" · epoch {g.epoch}"
    | none => ""
  s!"{m.network}{epoch} · {pending} to write"

def statusBar (m : Model) : Node Msg :=
  Ui.pad (px 6) <| Ui.row [Ui.caption (Display.text (status m)) "status", Ui.spacer,
    Ui.caption (Display.text m.note) "note"] (px 12)

def accept (caption : String) (kind : Widgets.ButtonKind) : Node Msg :=
  Node.leaf (Widgets.button (SafeText.trusted caption) .confirm (designated := true) (kind := kind)) "accept"

def dialogView (m : Model) (d : Dialog) : Node Msg :=
  let group := (Display.name (d.chat.getD "")).text
  let field (placeholder : String) :=
    Ui.textField d.field .field { placeholder := SafeText.trusted placeholder } "dialog-field"
  let buttons (caption : String) (kind : Widgets.ButtonKind) :=
    Ui.row [Ui.spacer, Ui.button "Cancel" .dismiss "cancel", accept caption kind] (px 6)
  let note := if d.note.isEmpty then [] else
    [Ui.text (Display.text d.note) (maxLines := 3) (key := "dialog-note") (tone := .error)]
  let body (title : String) (parts : List (Node Msg)) (caption : String) (kind : Widgets.ButtonKind) :=
    Ui.dialog d.modal (SafeName.filter title)
      (Ui.width (px 420) (Ui.col ([Node.leaf (Widgets.label (SafeText.trusted title) (bold := true) (size := .heading))] ++
        parts ++ note ++ [buttons caption kind]) (px 12))) .dismiss
  match d.kind with
  | .newGroup => body "New group"
      [Ui.paragraph "A group of your own; you add members with Invite.", field "its name"] "Create" .main
  | .join => body "Join a group"
      [Ui.paragraph ("Name it as you will know it here. A voucher code will appear: give it to a " ++
        "member of the group, who adds you with Invite."), field "its name here"] "Join" .main
  | .invite => body s!"Invite to {group}"
      [Ui.paragraph s!"Whoever holds this code will read everything said in {group} from now on.",
        field "voucher code"] "Invite" .main
  | .remove =>
    let others := ((m.state.chat? (d.chat.getD "")).map (Display.members m.state.me ·)).getD [] |>.drop 1
    let hexes := others.map (Display.hex ·.key)
    let label (h : String) := ((others.find? (Display.hex ·.key == h)).map fun mb =>
      mb.label.text ++ s!" {Display.fingerprint mb.key}").getD h
    let chosen := (d.pick.map label).getD "The member you choose"
    body s!"Remove a member of {group}"
      [Ui.selectList hexes d.pick .pick label ("pick:" ++ ·) (rows := 6) (key := "members"),
        Ui.paragraph s!"{chosen} will no longer be read here; what they sent is deleted here. They can still read {group}."]
      "Remove" .destructive
  | .leave => body s!"Leave {group}"
      [Ui.paragraph s!"Leave {group} and delete it here? This cannot be undone. Type its name to confirm.",
        field "the group's name"] "Leave" .destructive
  | .clear => body s!"Clear {group}"
      [Ui.paragraph s!"Delete this conversation's lines here? The other members keep theirs."] "Clear" .destructive

def bindings : List (Widgets.KeyCombo × Msg) :=
  [({ key := .char 'q', ctrl := true }, .quit), ({ key := .f 10 }, .toggleBlank),
   ({ key := .f 2 }, .toggleLog), ({ key := .pageDown, ctrl := true }, .next true),
   ({ key := .pageUp, ctrl := true }, .next false)]

def view (m : Model) : Node Msg :=
  Ui.keystroke bindings <| Ui.themed (if m.dark then Theme.dark else Theme.light) <|
  if m.blank then Ui.pad (px 24) (Ui.label "glint · F10 to return" "blank") else
  let (middle, right) := match m.current with
    | some c => (conversationPane m c, membersPane m c)
    | none => (empty, Ui.surface Ui.spacer)
  let panes := Ui.split (groupsPane m) (Ui.split middle right m.inner (.ratio false) (key := "inner"))
    m.outer (.ratio true) (key := "outer")
  Ui.col ([panes] ++ (if m.showLog then [rule, logPane m] else []) ++
    [rule, statusBar m] ++ (m.dialog.toList.map (dialogView m))) 0

def app (post : GroupChatKatzenqt1.Msg → IO Unit) (init : Model) (start : List (Cmd Msg caps .other) := []) :
    App caps :=
  { Model := Model, Msg := Msg, init, update := update post, view, start }

end Glint.App
