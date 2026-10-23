/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Sigil.Display
import GroupChatClient.GroupChatKatzenqt1.Presentation

/-! # How sigil words and filters what the core says -/

namespace Sigil

open GroupChatClient.GroupChatKatzenqt1

def presentation : Presentation where
  name s := (Display.name s).text
  outgoing := Display.outgoing
  newGroup := "a new group: Invite, with a member's voucher code, adds them"
  voucherMinted _ _ file :=
    s!"give the voucher code shown above to a member of the group, who adds you with Invite (it is also in {file} in the state directory)"

end Sigil
