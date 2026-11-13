// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ApprovedSender
/// @notice Sends TRC20 tokens between wallet addresses. Only approved wallets can send,
///         and approved wallets can approve or remove other wallets.
/// @dev    Two ways to send, both limited to approved callers:
///         - send / sendBatch: tokens held by this contract go to `to`.
///         - sendFromSelf:     the caller's OWN tokens (via allowance) go to `to`.
///         Nobody, approved or not, can move tokens out of any other wallet.
///         Token transfers are checked by balance change, not by the return value,
///         because Tron's USDT contract returns false from transfer() even on success.
///         Supported: standard TRC20 tokens and USDT-style tokens (false or no return value).
///         Not supported (calls revert): rebasing, reflection and sender-pays-fee tokens.
interface ITRC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract ApprovedSender {
    address[] private _wallets;
    mapping(address => uint256) private _position; // index in _wallets + 1; 0 = not approved

    uint256 private _lock = 1;

    event WalletApproved(address indexed wallet, address indexed by);
    event WalletRemoved(address indexed wallet, address indexed by);
    /// @dev `amount` is what the sender was debited; a fee-on-transfer token may pass on less.
    event Sent(address indexed token, address indexed by, address indexed to, uint256 amount);
    event SentFromSelf(address indexed token, address indexed from, address indexed to, uint256 amount);
    event SentTRX(address indexed by, address indexed to, uint256 amountSun);

    error NotApproved(address caller);
    error InvalidWallet(address wallet);
    error AlreadyApproved(address wallet);
    error NotInList(address wallet);
    error LastApprovedWallet();
    error ZeroAmount();
    error BadRecipient(address to);
    error LengthMismatch();
    error EmptyList();
    error TransferFailed(address token);
    error NotAContract(address token);
    error Reentrancy();
    error BatchTooLarge(uint256 length);

    /// @notice Upper bound for sendBatch, so a huge batch cannot hit TRON's per-transaction
    ///         CPU time limit (which burns the whole fee limit).
    uint256 public constant MAX_BATCH = 100;

    modifier onlyApproved() {
        if (_position[msg.sender] == 0) revert NotApproved(msg.sender);
        _;
    }

    modifier nonReentrant() {
        if (_lock != 1) revert Reentrancy();
        _lock = 2;
        _;
        _lock = 1;
    }

    /// @param initialWallets first approved wallets (at least one, no duplicates,
    ///        not the zero address and not this contract).
    constructor(address[] memory initialWallets) {
        if (initialWallets.length == 0) revert EmptyList();
        for (uint256 i = 0; i < initialWallets.length; i++) {
            _approve(initialWallets[i]);
        }
    }

    // ----------------------------------------------------------------- wallet list

    function isApproved(address wallet) external view returns (bool) {
        return _position[wallet] != 0;
    }

    function approvedCount() external view returns (uint256) {
        return _wallets.length;
    }

    /// @notice All approved wallets (order changes when a wallet is removed).
    function approvedWallets() external view returns (address[] memory) {
        return _wallets;
    }

    function approveWallet(address wallet) external onlyApproved {
        _approve(wallet);
    }

    /// @notice Removes a wallet (also yourself). At least one address always stays approved;
    ///         make sure you control the wallets you keep, or tokens in the contract are stuck.
    function removeWallet(address wallet) external onlyApproved {
        uint256 pos = _position[wallet];
        if (pos == 0) revert NotInList(wallet);
        if (_wallets.length == 1) revert LastApprovedWallet();
        address last = _wallets[_wallets.length - 1];
        _wallets[pos - 1] = last;
        _position[last] = pos;
        _wallets.pop();
        delete _position[wallet];
        emit WalletRemoved(wallet, msg.sender);
    }

    function _approve(address wallet) private {
        if (wallet == address(0) || wallet == address(this)) revert InvalidWallet(wallet);
        if (_position[wallet] != 0) revert AlreadyApproved(wallet);
        _wallets.push(wallet);
        _position[wallet] = _wallets.length;
        emit WalletApproved(wallet, msg.sender);
    }

    // ----------------------------------------------------------------- sending

    /// @notice Sends `amount` of `token` held by this contract to `to`.
    function send(address token, address to, uint256 amount) external onlyApproved nonReentrant {
        _sendFromContract(token, to, amount);
    }

    /// @notice Sends tokens held by this contract to several recipients in one transaction.
    ///         All-or-nothing: if one transfer fails, the whole batch reverts.
    function sendBatch(address token, address[] calldata to, uint256[] calldata amounts)
        external
        onlyApproved
        nonReentrant
    {
        if (to.length == 0) revert EmptyList();
        if (to.length != amounts.length) revert LengthMismatch();
        if (to.length > MAX_BATCH) revert BatchTooLarge(to.length);
        for (uint256 i = 0; i < to.length; i++) {
            _sendFromContract(token, to[i], amounts[i]);
        }
    }

    /// @notice Sends the CALLER'S OWN tokens to `to`. The caller must first approve this
    ///         contract for at least `amount` on the token contract.
    function sendFromSelf(address token, address to, uint256 amount) external onlyApproved nonReentrant {
        _checkArgs(token, to, amount);
        if (to == msg.sender) revert BadRecipient(to);
        uint256 before = ITRC20(token).balanceOf(msg.sender);
        _call(token, abi.encodeWithSelector(ITRC20.transferFrom.selector, msg.sender, to, amount));
        _checkDebited(token, before, ITRC20(token).balanceOf(msg.sender), amount);
        emit SentFromSelf(token, msg.sender, to, amount);
    }

    /// @notice Sends TRX held by this contract (TRX can arrive with a plain transfer even
    ///         though the contract has no payable function; this gets it back out).
    /// @param amountSun amount in sun (1 TRX = 1,000,000 sun).
    function sendTRX(address payable to, uint256 amountSun) external onlyApproved nonReentrant {
        if (to == address(0) || to == address(this)) revert BadRecipient(to);
        if (amountSun == 0) revert ZeroAmount();
        (bool ok, ) = to.call{value: amountSun}("");
        if (!ok) revert TransferFailed(address(0));
        emit SentTRX(msg.sender, to, amountSun);
    }

    /// @notice Amount of `token` held by this contract.
    function tokenBalance(address token) external view returns (uint256) {
        return ITRC20(token).balanceOf(address(this));
    }

    function _sendFromContract(address token, address to, uint256 amount) private {
        _checkArgs(token, to, amount);
        uint256 before = ITRC20(token).balanceOf(address(this));
        _call(token, abi.encodeWithSelector(ITRC20.transfer.selector, to, amount));
        _checkDebited(token, before, ITRC20(token).balanceOf(address(this)), amount);
        emit Sent(token, msg.sender, to, amount);
    }

    function _checkArgs(address token, address to, uint256 amount) private view {
        if (token.code.length == 0) revert NotAContract(token);
        if (to == address(0) || to == address(this) || to == token) revert BadRecipient(to);
        if (amount == 0) revert ZeroAmount();
    }

    /// @dev The sender's balance must go down by exactly `amount`.
    function _checkDebited(address token, uint256 before, uint256 afterwards, uint256 amount) private pure {
        if (afterwards > before || before - afterwards != amount) revert TransferFailed(token);
    }

    /// @dev Reverts if the token call reverts (passing on the token's reason). The return
    ///      value is deliberately ignored: success is judged by the balance change.
    function _call(address token, bytes memory data) private {
        (bool ok, bytes memory ret) = token.call(data);
        if (!ok) {
            if (ret.length > 0) {
                assembly {
                    revert(add(ret, 32), mload(ret))
                }
            }
            revert TransferFailed(token);
        }
    }
}
