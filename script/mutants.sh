#!/usr/bin/env bash
# Breaks the contract on purpose, one change at a time, and checks that at least one test
# fails for each change ("killed"). Run from the repo root: bash script/mutants.sh
set -u
FORGE="${FORGE:-forge}"
SRC=src/ApprovedSender.sol
ORIG=$(mktemp)
cp "$SRC" "$ORIG"
trap 'cp "$ORIG" "$SRC"; rm -f "$ORIG"' EXIT
survived=0
mutate() {
  local name="$1" from="$2" to="$3"
  python3 - "$ORIG" "$SRC" "$from" "$to" <<'PY' || { echo "$name: pattern not found"; survived=1; return; }
import sys
orig, out, a, b = sys.argv[1:5]
s = open(orig).read()
if a not in s:
    sys.exit(1)
open(out, "w").write(s.replace(a, b, 1))
PY
  if "$FORGE" test >/dev/null 2>&1; then echo "SURVIVED  $name"; survived=1; else echo "killed    $name"; fi
  cp "$ORIG" "$SRC"
}
mutate batch_no_lock $'        onlyApproved\n        nonReentrant\n    {' $'        onlyApproved\n    {'
mutate self_no_lock "external onlyApproved nonReentrant {
        _checkArgs(token, to, amount);
        if (to == msg.sender)" "external onlyApproved {
        _checkArgs(token, to, amount);
        if (to == msg.sender)"
mutate send_no_lock "function send(address token, address to, uint256 amount) external onlyApproved nonReentrant" "function send(address token, address to, uint256 amount) external onlyApproved"
mutate no_SentFromSelf_event "        emit SentFromSelf(token, msg.sender, to, amount);" ""
mutate no_Sent_event "        emit Sent(token, msg.sender, to, amount);" ""
mutate no_WalletApproved_event "        emit WalletApproved(wallet, msg.sender);" ""
mutate no_WalletRemoved_event "        emit WalletRemoved(wallet, msg.sender);" ""
mutate debit_check_lt "before - afterwards != amount" "before - afterwards < amount"
mutate no_balance_up_check "afterwards > before || " ""
mutate no_last_wallet_rule "        if (_wallets.length == 1) revert LastApprovedWallet();" ""
mutate allow_self_as_wallet "wallet == address(0) || wallet == address(this)" "wallet == address(0)"
mutate allow_send_to_self "        if (to == msg.sender) revert BadRecipient(to);" ""
mutate list_swap_bug "        _position[last] = pos;" ""
mutate no_access_check "        if (_position[msg.sender] == 0) revert NotApproved(msg.sender);" ""
mutate no_batch_cap "        if (to.length > MAX_BATCH) revert BatchTooLarge(to.length);" ""
mutate trx_no_lock "function sendTRX(address payable to, uint256 amountSun) external onlyApproved nonReentrant" "function sendTRX(address payable to, uint256 amountSun) external onlyApproved"
mutate no_SentTRX_event "        emit SentTRX(msg.sender, to, amountSun);" ""
exit $survived
