// SPDX-License-Identifier: MIT
pragma solidity >=0.8.6 <0.9.0;

/// Standard TRC20: returns true.
contract StdToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 a) external { balanceOf[to] += a; }

    function approve(address s, uint256 a) external returns (bool) { allowance[msg.sender][s] = a; return true; }

    function transfer(address to, uint256 a) external virtual returns (bool) {
        _move(msg.sender, to, a);
        return true;
    }

    function transferFrom(address f, address to, uint256 a) external virtual returns (bool) {
        require(allowance[f][msg.sender] >= a, "allowance");
        allowance[f][msg.sender] -= a;
        _move(f, to, a);
        return true;
    }

    function _move(address f, address to, uint256 a) internal {
        require(balanceOf[f] >= a, "balance");
        balanceOf[f] -= a;
        balanceOf[to] += a;
    }
}

/// Like Tron mainnet USDT: transfer() moves the tokens but returns false.
contract TronUsdtLike is StdToken {
    function transfer(address to, uint256 a) external override returns (bool) {
        _move(msg.sender, to, a);
        return false;
    }
}

/// Old-style token with no return value at all.
contract NoReturnToken {
    mapping(address => uint256) public balanceOf;
    function mint(address to, uint256 a) external { balanceOf[to] += a; }
    function transfer(address to, uint256 a) external {
        require(balanceOf[msg.sender] >= a, "balance");
        balanceOf[msg.sender] -= a;
        balanceOf[to] += a;
    }
}

/// Broken token: says true but moves nothing.
contract LyingToken is StdToken {
    function transfer(address, uint256) external pure override returns (bool) { return true; }
    function transferFrom(address, address, uint256) external pure override returns (bool) { return true; }
}

/// Token that calls back into a target with a stored payload during transfer/transferFrom
/// (used to prove the re-entrancy lock on send, sendBatch and sendFromSelf).
contract ReentrantToken is StdToken {
    address public target;
    bytes public payload;

    function arm(address t, bytes calldata p) external { target = t; payload = p; }

    function transfer(address to, uint256 a) external override returns (bool) {
        _move(msg.sender, to, a);
        _reenter();
        return true;
    }

    function transferFrom(address f, address to, uint256 a) external override returns (bool) {
        require(allowance[f][msg.sender] >= a, "allowance");
        allowance[f][msg.sender] -= a;
        _move(f, to, a);
        _reenter();
        return true;
    }

    // One-shot: re-enters once, so a missing lock on the OUTER function shows up
    // instead of being hidden by the inner call's own lock.
    function _reenter() internal {
        address t = target;
        if (t == address(0)) return;
        target = address(0);
        (bool ok, bytes memory ret) = t.call(payload);
        if (!ok) { assembly { revert(add(ret, 32), mload(ret)) } }
    }
}

/// Takes one unit more than asked from the sender.
contract OverdebitToken is StdToken {
    function transfer(address to, uint256 a) external override returns (bool) {
        _move(msg.sender, to, a);
        _move(msg.sender, address(0xdead), 1);
        return true;
    }
}

/// Sender's balance goes UP during the transfer (reflection-style reward).
contract BalanceUpToken is StdToken {
    function transfer(address to, uint256 a) external override returns (bool) {
        _move(msg.sender, to, a);
        balanceOf[msg.sender] += a + 1;
        return true;
    }
}

/// Like USDT on transfer, but on transferFrom: moves the tokens and returns false.
contract FalseFromToken is StdToken {
    function transferFrom(address f, address to, uint256 a) external override returns (bool) {
        require(allowance[f][msg.sender] >= a, "allowance");
        allowance[f][msg.sender] -= a;
        _move(f, to, a);
        return false;
    }
}

/// TRX receiver that calls sendTRX again (once) when it gets paid.
contract ReentrantReceiver {
    address public target;
    bool private fired;

    function setTarget(address t) external { target = t; }

    receive() external payable {
        if (fired) return;
        fired = true;
        (bool ok, bytes memory ret) =
            target.call(abi.encodeWithSignature("sendTRX(address,uint256)", address(this), 1));
        if (!ok) { assembly { revert(add(ret, 32), mload(ret)) } }
    }
}
