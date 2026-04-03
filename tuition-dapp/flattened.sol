

// Sources flattened with hardhat v2.28.6 https://hardhat.org

// SPDX-License-Identifier: MIT

// File @openzeppelin/contracts/access/IAccessControl.sol@v5.6.1

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.4.0) (access/IAccessControl.sol)

pragma solidity >=0.8.4;

/**
 * @dev External interface of AccessControl declared to support ERC-165 detection.
 */
interface IAccessControl {
    /**
     * @dev The `account` is missing a role.
     */
    error AccessControlUnauthorizedAccount(address account, bytes32 neededRole);

    /**
     * @dev The caller of a function is not the expected one.
     *
     * NOTE: Don't confuse with {AccessControlUnauthorizedAccount}.
     */
    error AccessControlBadConfirmation();

    /**
     * @dev Emitted when `newAdminRole` is set as ``role``'s admin role, replacing `previousAdminRole`
     *
     * `DEFAULT_ADMIN_ROLE` is the starting admin for all roles, despite
     * {RoleAdminChanged} not being emitted to signal this.
     */
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);

    /**
     * @dev Emitted when `account` is granted `role`.
     *
     * `sender` is the account that originated the contract call. This account bears the admin role (for the granted role).
     * Expected in cases where the role was granted using the internal {AccessControl-_grantRole}.
     */
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);

    /**
     * @dev Emitted when `account` is revoked `role`.
     *
     * `sender` is the account that originated the contract call:
     *   - if using `revokeRole`, it is the admin role bearer
     *   - if using `renounceRole`, it is the role bearer (i.e. `account`)
     */
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    /**
     * @dev Returns `true` if `account` has been granted `role`.
     */
    function hasRole(bytes32 role, address account) external view returns (bool);

    /**
     * @dev Returns the admin role that controls `role`. See {grantRole} and
     * {revokeRole}.
     *
     * To change a role's admin, use {AccessControl-_setRoleAdmin}.
     */
    function getRoleAdmin(bytes32 role) external view returns (bytes32);

    /**
     * @dev Grants `role` to `account`.
     *
     * If `account` had not been already granted `role`, emits a {RoleGranted}
     * event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     */
    function grantRole(bytes32 role, address account) external;

    /**
     * @dev Revokes `role` from `account`.
     *
     * If `account` had been granted `role`, emits a {RoleRevoked} event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     */
    function revokeRole(bytes32 role, address account) external;

    /**
     * @dev Revokes `role` from the calling account.
     *
     * Roles are often managed via {grantRole} and {revokeRole}: this function's
     * purpose is to provide a mechanism for accounts to lose their privileges
     * if they are compromised (such as when a trusted device is misplaced).
     *
     * If the calling account had been granted `role`, emits a {RoleRevoked}
     * event.
     *
     * Requirements:
     *
     * - the caller must be `callerConfirmation`.
     */
    function renounceRole(bytes32 role, address callerConfirmation) external;
}


// File @openzeppelin/contracts/utils/Context.sol@v5.6.1

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.1) (utils/Context.sol)

pragma solidity ^0.8.20;

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 0;
    }
}


// File @openzeppelin/contracts/utils/introspection/IERC165.sol@v5.6.1

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.4.0) (utils/introspection/IERC165.sol)

pragma solidity >=0.4.16;

/**
 * @dev Interface of the ERC-165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[ERC].
 *
 * Implementers can declare support of contract interfaces, which can then be
 * queried by others ({ERC165Checker}).
 *
 * For an implementation, see {ERC165}.
 */
interface IERC165 {
    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[ERC section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}


// File @openzeppelin/contracts/utils/introspection/ERC165.sol@v5.6.1

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.4.0) (utils/introspection/ERC165.sol)

pragma solidity ^0.8.20;

/**
 * @dev Implementation of the {IERC165} interface.
 *
 * Contracts that want to implement ERC-165 should inherit from this contract and override {supportsInterface} to check
 * for the additional interface id that will be supported. For example:
 *
 * ```solidity
 * function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
 *     return interfaceId == type(MyInterface).interfaceId || super.supportsInterface(interfaceId);
 * }
 * ```
 */
abstract contract ERC165 is IERC165 {
    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}


// File @openzeppelin/contracts/access/AccessControl.sol@v5.6.1

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.6.0) (access/AccessControl.sol)

pragma solidity ^0.8.20;



/**
 * @dev Contract module that allows children to implement role-based access
 * control mechanisms. This is a lightweight version that doesn't allow enumerating role
 * members except through off-chain means by accessing the contract event logs. Some
 * applications may benefit from on-chain enumerability, for those cases see
 * {AccessControlEnumerable}.
 *
 * Roles are referred to by their `bytes32` identifier. These should be exposed
 * in the external API and be unique. The best way to achieve this is by
 * using `public constant` hash digests:
 *
 * ```solidity
 * bytes32 public constant MY_ROLE = keccak256("MY_ROLE");
 * ```
 *
 * Roles can be used to represent a set of permissions. To restrict access to a
 * function call, use {hasRole}:
 *
 * ```solidity
 * function foo() public {
 *     require(hasRole(MY_ROLE, msg.sender));
 *     ...
 * }
 * ```
 *
 * Roles can be granted and revoked dynamically via the {grantRole} and
 * {revokeRole} functions. Each role has an associated admin role, and only
 * accounts that have a role's admin role can call {grantRole} and {revokeRole}.
 *
 * By default, the admin role for all roles is `DEFAULT_ADMIN_ROLE`, which means
 * that only accounts with this role will be able to grant or revoke other
 * roles. More complex role relationships can be created by using
 * {_setRoleAdmin}.
 *
 * WARNING: The `DEFAULT_ADMIN_ROLE` is also its own admin: it has permission to
 * grant and revoke this role. Extra precautions should be taken to secure
 * accounts that have been granted it. We recommend using {AccessControlDefaultAdminRules}
 * to enforce additional security measures for this role.
 */
abstract contract AccessControl is Context, IAccessControl, ERC165 {
    struct RoleData {
        mapping(address account => bool) hasRole;
        bytes32 adminRole;
    }

    mapping(bytes32 role => RoleData) private _roles;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    /**
     * @dev Modifier that checks that an account has a specific role. Reverts
     * with an {AccessControlUnauthorizedAccount} error including the required role.
     */
    modifier onlyRole(bytes32 role) {
        _checkRole(role);
        _;
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IAccessControl).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev Returns `true` if `account` has been granted `role`.
     */
    function hasRole(bytes32 role, address account) public view virtual returns (bool) {
        return _roles[role].hasRole[account];
    }

    /**
     * @dev Reverts with an {AccessControlUnauthorizedAccount} error if `_msgSender()`
     * is missing `role`. Overriding this function changes the behavior of the {onlyRole} modifier.
     */
    function _checkRole(bytes32 role) internal view virtual {
        _checkRole(role, _msgSender());
    }

    /**
     * @dev Reverts with an {AccessControlUnauthorizedAccount} error if `account`
     * is missing `role`.
     */
    function _checkRole(bytes32 role, address account) internal view virtual {
        if (!hasRole(role, account)) {
            revert AccessControlUnauthorizedAccount(account, role);
        }
    }

    /**
     * @dev Returns the admin role that controls `role`. See {grantRole} and
     * {revokeRole}.
     *
     * To change a role's admin, use {_setRoleAdmin}.
     */
    function getRoleAdmin(bytes32 role) public view virtual returns (bytes32) {
        return _roles[role].adminRole;
    }

    /**
     * @dev Grants `role` to `account`.
     *
     * If `account` had not been already granted `role`, emits a {RoleGranted}
     * event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     *
     * May emit a {RoleGranted} event.
     */
    function grantRole(bytes32 role, address account) public virtual onlyRole(getRoleAdmin(role)) {
        _grantRole(role, account);
    }

    /**
     * @dev Revokes `role` from `account`.
     *
     * If `account` had been granted `role`, emits a {RoleRevoked} event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     *
     * May emit a {RoleRevoked} event.
     */
    function revokeRole(bytes32 role, address account) public virtual onlyRole(getRoleAdmin(role)) {
        _revokeRole(role, account);
    }

    /**
     * @dev Revokes `role` from the calling account.
     *
     * Roles are often managed via {grantRole} and {revokeRole}: this function's
     * purpose is to provide a mechanism for accounts to lose their privileges
     * if they are compromised (such as when a trusted device is misplaced).
     *
     * If the calling account had been revoked `role`, emits a {RoleRevoked}
     * event.
     *
     * Requirements:
     *
     * - the caller must be `callerConfirmation`.
     *
     * May emit a {RoleRevoked} event.
     */
    function renounceRole(bytes32 role, address callerConfirmation) public virtual {
        if (callerConfirmation != _msgSender()) {
            revert AccessControlBadConfirmation();
        }

        _revokeRole(role, callerConfirmation);
    }

    /**
     * @dev Sets `adminRole` as ``role``'s admin role.
     *
     * Emits a {RoleAdminChanged} event.
     */
    function _setRoleAdmin(bytes32 role, bytes32 adminRole) internal virtual {
        bytes32 previousAdminRole = getRoleAdmin(role);
        _roles[role].adminRole = adminRole;
        emit RoleAdminChanged(role, previousAdminRole, adminRole);
    }

    /**
     * @dev Attempts to grant `role` to `account` and returns a boolean indicating if `role` was granted.
     *
     * Internal function without access restriction.
     *
     * May emit a {RoleGranted} event.
     */
    function _grantRole(bytes32 role, address account) internal virtual returns (bool) {
        if (!hasRole(role, account)) {
            _roles[role].hasRole[account] = true;
            emit RoleGranted(role, account, _msgSender());
            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Attempts to revoke `role` from `account` and returns a boolean indicating if `role` was revoked.
     *
     * Internal function without access restriction.
     *
     * May emit a {RoleRevoked} event.
     */
    function _revokeRole(bytes32 role, address account) internal virtual returns (bool) {
        if (hasRole(role, account)) {
            _roles[role].hasRole[account] = false;
            emit RoleRevoked(role, account, _msgSender());
            return true;
        } else {
            return false;
        }
    }
}


// File @openzeppelin/contracts/utils/Pausable.sol@v5.6.1

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.3.0) (utils/Pausable.sol)

pragma solidity ^0.8.20;

/**
 * @dev Contract module which allows children to implement an emergency stop
 * mechanism that can be triggered by an authorized account.
 *
 * This module is used through inheritance. It will make available the
 * modifiers `whenNotPaused` and `whenPaused`, which can be applied to
 * the functions of your contract. Note that they will not be pausable by
 * simply including this module, only once the modifiers are put in place.
 */
abstract contract Pausable is Context {
    bool private _paused;

    /**
     * @dev Emitted when the pause is triggered by `account`.
     */
    event Paused(address account);

    /**
     * @dev Emitted when the pause is lifted by `account`.
     */
    event Unpaused(address account);

    /**
     * @dev The operation failed because the contract is paused.
     */
    error EnforcedPause();

    /**
     * @dev The operation failed because the contract is not paused.
     */
    error ExpectedPause();

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    modifier whenPaused() {
        _requirePaused();
        _;
    }

    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     */
    function paused() public view virtual returns (bool) {
        return _paused;
    }

    /**
     * @dev Throws if the contract is paused.
     */
    function _requireNotPaused() internal view virtual {
        if (paused()) {
            revert EnforcedPause();
        }
    }

    /**
     * @dev Throws if the contract is not paused.
     */
    function _requirePaused() internal view virtual {
        if (!paused()) {
            revert ExpectedPause();
        }
    }

    /**
     * @dev Triggers stopped state.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
    }
}


// File @openzeppelin/contracts/utils/StorageSlot.sol@v5.6.1

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (utils/StorageSlot.sol)
// This file was procedurally generated from scripts/generate/templates/StorageSlot.js.

pragma solidity ^0.8.20;

/**
 * @dev Library for reading and writing primitive types to specific storage slots.
 *
 * Storage slots are often used to avoid storage conflict when dealing with upgradeable contracts.
 * This library helps with reading and writing to such slots without the need for inline assembly.
 *
 * The functions in this library return Slot structs that contain a `value` member that can be used to read or write.
 *
 * Example usage to set ERC-1967 implementation slot:
 * ```solidity
 * contract ERC1967 {
 *     // Define the slot. Alternatively, use the SlotDerivation library to derive the slot.
 *     bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
 *
 *     function _getImplementation() internal view returns (address) {
 *         return StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value;
 *     }
 *
 *     function _setImplementation(address newImplementation) internal {
 *         require(newImplementation.code.length > 0);
 *         StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value = newImplementation;
 *     }
 * }
 * ```
 *
 * TIP: Consider using this library along with {SlotDerivation}.
 */
library StorageSlot {
    struct AddressSlot {
        address value;
    }

    struct BooleanSlot {
        bool value;
    }

    struct Bytes32Slot {
        bytes32 value;
    }

    struct Uint256Slot {
        uint256 value;
    }

    struct Int256Slot {
        int256 value;
    }

    struct StringSlot {
        string value;
    }

    struct BytesSlot {
        bytes value;
    }

    /**
     * @dev Returns an `AddressSlot` with member `value` located at `slot`.
     */
    function getAddressSlot(bytes32 slot) internal pure returns (AddressSlot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `BooleanSlot` with member `value` located at `slot`.
     */
    function getBooleanSlot(bytes32 slot) internal pure returns (BooleanSlot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `Bytes32Slot` with member `value` located at `slot`.
     */
    function getBytes32Slot(bytes32 slot) internal pure returns (Bytes32Slot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `Uint256Slot` with member `value` located at `slot`.
     */
    function getUint256Slot(bytes32 slot) internal pure returns (Uint256Slot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `Int256Slot` with member `value` located at `slot`.
     */
    function getInt256Slot(bytes32 slot) internal pure returns (Int256Slot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `StringSlot` with member `value` located at `slot`.
     */
    function getStringSlot(bytes32 slot) internal pure returns (StringSlot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `StringSlot` representation of the string storage pointer `store`.
     */
    function getStringSlot(string storage store) internal pure returns (StringSlot storage r) {
        assembly ("memory-safe") {
            r.slot := store.slot
        }
    }

    /**
     * @dev Returns a `BytesSlot` with member `value` located at `slot`.
     */
    function getBytesSlot(bytes32 slot) internal pure returns (BytesSlot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `BytesSlot` representation of the bytes storage pointer `store`.
     */
    function getBytesSlot(bytes storage store) internal pure returns (BytesSlot storage r) {
        assembly ("memory-safe") {
            r.slot := store.slot
        }
    }
}


// File @openzeppelin/contracts/utils/ReentrancyGuard.sol@v5.6.1

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.5.0) (utils/ReentrancyGuard.sol)

pragma solidity ^0.8.20;

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If EIP-1153 (transient storage) is available on the chain you're deploying at,
 * consider using {ReentrancyGuardTransient} instead.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 *
 * IMPORTANT: Deprecated. This storage-based reentrancy guard will be removed and replaced
 * by the {ReentrancyGuardTransient} variant in v6.0.
 *
 * @custom:stateless
 */
abstract contract ReentrancyGuard {
    using StorageSlot for bytes32;

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ReentrancyGuard")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant REENTRANCY_GUARD_STORAGE =
        0x9b779b17422d0df92223018b32b4d1fa46e071723d6817e2486d003becc55f00;

    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    /**
     * @dev Unauthorized reentrant call.
     */
    error ReentrancyGuardReentrantCall();

    constructor() {
        _reentrancyGuardStorageSlot().getUint256Slot().value = NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    /**
     * @dev A `view` only version of {nonReentrant}. Use to block view functions
     * from being called, preventing reading from inconsistent contract state.
     *
     * CAUTION: This is a "view" modifier and does not change the reentrancy
     * status. Use it only on view functions. For payable or non-payable functions,
     * use the standard {nonReentrant} modifier instead.
     */
    modifier nonReentrantView() {
        _nonReentrantBeforeView();
        _;
    }

    function _nonReentrantBeforeView() private view {
        if (_reentrancyGuardEntered()) {
            revert ReentrancyGuardReentrantCall();
        }
    }

    function _nonReentrantBefore() private {
        // On the first call to nonReentrant, _status will be NOT_ENTERED
        _nonReentrantBeforeView();

        // Any calls to nonReentrant after this point will fail
        _reentrancyGuardStorageSlot().getUint256Slot().value = ENTERED;
    }

    function _nonReentrantAfter() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _reentrancyGuardStorageSlot().getUint256Slot().value = NOT_ENTERED;
    }

    /**
     * @dev Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
     * `nonReentrant` function in the call stack.
     */
    function _reentrancyGuardEntered() internal view returns (bool) {
        return _reentrancyGuardStorageSlot().getUint256Slot().value == ENTERED;
    }

    function _reentrancyGuardStorageSlot() internal pure virtual returns (bytes32) {
        return REENTRANCY_GUARD_STORAGE;
    }
}


// File @chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol@v1.5.0

// Original license: SPDX_License_Identifier: MIT
pragma solidity ^0.8.0;

// solhint-disable-next-line interface-starts-with-i
interface AggregatorV3Interface {
  function decimals() external view returns (uint8);

  function description() external view returns (string memory);

  function version() external view returns (uint256);

  function getRoundData(
    uint80 _roundId
  ) external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

  function latestRoundData()
    external
    view
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}


// File @openzeppelin/contracts/token/ERC20/IERC20.sol@v5.6.1

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.4.0) (token/ERC20/IERC20.sol)

pragma solidity >=0.4.16;

/**
 * @dev Interface of the ERC-20 standard as defined in the ERC.
 */
interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the value of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}


// File contracts/TuitionPayment.sol

pragma solidity ^0.8.20;





/**
 * @title TuitionPayment
 * @notice Escrow-based tuition payment system on Polygon PoS using USDC.
 *         Students deposit USDC into per-student escrow; admin executes
 *         batch payment to the university wallet on the due date.
 *
 *         Integrates Chainlink Price Feeds to provide a locked JPY/USD
 *         rate each semester, allowing students to see the JPY equivalent
 *         of their USDC fees. All payments are denominated in USDC.
 *
 *         Security: AccessControl (RBAC), ReentrancyGuard, Pausable,
 *         CEI pattern on all state-changing functions, bounded batch size,
 *         deposit rate limiting, deposit cap, oracle staleness check.
 *
 * @dev    All monetary values use USDC's 6-decimal representation.
 *         Chainlink FX feeds return 8-decimal values.
 *
 *         FX feed direction: This contract expects a JPY/USD feed
 *         (i.e. "how many USD per 1 JPY"). Chainlink's JPY/USD feed
 *         on Polygon returns values like 670000 (= 0.00670000 USD/JPY
 *         at 8 decimals). Do NOT use a USD/JPY feed — the conversion
 *         math in calculateFeesInJPY() would be inverted.
 */
contract TuitionPayment is AccessControl, ReentrancyGuard, Pausable {

    // ========================
    // ROLES
    // ========================
    bytes32 public constant ADMIN_ROLE   = keccak256("ADMIN_ROLE");
    bytes32 public constant STUDENT_ROLE = keccak256("STUDENT_ROLE");

    // ========================
    // CUSTOM ERRORS (gas-efficient, structured data for frontend)
    // ========================
    error StalePriceFeed(uint256 currentTime, uint256 updatedAt, uint256 threshold);
    error InvalidOraclePrice(int256 price);
    error DepositCooldownActive(address student, uint256 nextAllowedTime);
    error DepositExceedsFees(address student, uint256 newBalance, uint256 maxAllowed);
    error ZeroAddress();
    error ZeroHash();
    error HashAlreadyRegistered(bytes32 studentHash);
    error WalletAlreadyRegistered(address student);
    error StudentNotWhitelisted(address student);
    error CreditUnitsOutOfRange(uint256 units);
    error EmptyArray();
    error ArrayLengthMismatch();
    error BatchTooLarge(uint256 size);
    error ZeroAmount();
    error NoFundsAvailable(address student);
    error FxRateNotLocked();
    error PaymentDateNotSet();
    error PaymentDateNotReached(uint256 paymentDate, uint256 currentTime);
    error PaymentDateMustBeFuture();
    error FeesMustBePositive();
    error PaymentsAlreadyExecuted();
    error TransferFailed();

    // ========================
    // STATE
    // ========================
    IERC20  public immutable usdc;
    address public universityWallet;

    /// @notice Chainlink price feed — must be a JPY/USD feed (USD per 1 JPY)
    AggregatorV3Interface public priceFeed;

    /// @notice Per-student escrow balance (USDC, 6 decimals)
    mapping(address => uint256) public escrowBalance;

    /// @notice Credit units assigned to each student by admin
    mapping(address => uint256) public creditUnits;

    /// @notice Fee per credit unit in USDC (6 decimals)
    uint256 public feePerUnit;

    /// @notice Timestamp when payment will be pulled from escrow
    uint256 public paymentDate;

    /// @notice JPY/USD rate (8 decimals) locked by admin for the semester.
    ///         Stored as uint256 (the oracle staleness check in getLatestRate
    ///         guarantees the raw int256 value is positive before casting).
    uint256 public lockedFxRate;

    /// @notice Privacy layer: hashed student ID -> wallet address
    ///         Keeps plaintext student IDs off-chain only.
    mapping(bytes32 => address) public studentHashToWallet;

    /// @notice Reverse lookup: wallet address -> student hash
    ///         Required for cleanup when removing a student.
    mapping(address => bytes32) public walletToStudentHash;

    /// @notice Tracks whether a student's tuition has been paid for the
    ///         current semester. Set to true inside executePayment(),
    ///         reset by admin at the start of each new semester.
    mapping(address => bool) public paymentCompleted;

    /// @notice Rate limiting: tracks the last deposit timestamp per student.
    ///         Prevents deposit spam by enforcing a minimum cooldown period
    ///         between successive deposits from the same wallet.
    mapping(address => uint256) public lastDepositTime;

    /// @notice Tracks whether executePayment has been called this semester.
    ///         Used to guard setPaymentDate against post-execution changes.
    bool public paymentsExecutedThisSemester;

    // ========================
    // CONSTANTS / BOUNDS
    // ========================
    uint256 public constant MIN_CREDIT_UNITS    = 1;
    uint256 public constant MAX_CREDIT_UNITS    = 30;
    uint256 public constant MAX_BATCH_SIZE      = 50;
    uint256 public constant STALENESS_THRESHOLD = 1 hours;

    /// @notice Minimum time (in seconds) a student must wait between
    ///         successive deposit() calls. Prevents transaction spam.
    ///
    /// @dev    Set to 1 minute for the demo/POC. In production, this could
    ///         be adjusted based on operational needs — tuition deposits are
    ///         infrequent by nature, so even a longer cooldown (e.g. 10 min)
    ///         would not impact legitimate usage.
    uint256 public constant DEPOSIT_COOLDOWN = 1 minutes;

    // ========================
    // EVENTS
    // ========================
    event StudentWhitelisted(address indexed student, bytes32 indexed studentHash);
    event StudentRemoved(address indexed student, bytes32 indexed studentHash);
    event CreditUnitsSet(address indexed student, uint256 units);
    event Deposit(address indexed student, uint256 amount);
    event PaymentExecuted(
        address indexed student,
        uint256 amount,
        uint256 fxRate,
        uint256 timestamp
    );
    event InsufficientBalance(address indexed student, uint256 required, uint256 actual);
    event PaymentDateSet(uint256 date);
    event PaymentStatusReset(address indexed student);
    event EmergencyWithdrawal(address indexed student, uint256 amount);
    event Refund(address indexed student, uint256 amount);
    event UniversityWalletUpdated(address indexed oldWallet, address indexed newWallet);
    event FeePerUnitUpdated(uint256 oldFee, uint256 newFee);
    event PriceFeedUpdated(address indexed oldFeed, address indexed newFeed);
    event FxRateLocked(uint256 rate, uint256 timestamp);
    event FxRateReset(uint256 previousRate);

    // ========================
    // CONSTRUCTOR
    // ========================
    constructor(
        address _usdc,
        address _admin,
        address _universityWallet,
        uint256 _feePerUnit,
        address _priceFeed
    ) {
        if (_usdc == address(0))             revert ZeroAddress();
        if (_admin == address(0))            revert ZeroAddress();
        if (_universityWallet == address(0)) revert ZeroAddress();
        if (_feePerUnit == 0)                revert FeesMustBePositive();
        if (_priceFeed == address(0))        revert ZeroAddress();

        usdc = IERC20(_usdc);
        universityWallet = _universityWallet;
        feePerUnit = _feePerUnit;
        priceFeed = AggregatorV3Interface(_priceFeed);

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
    }

    // ================================================================
    //  CHAINLINK ORACLE
    // ================================================================

    /**
     * @notice Read the latest FX rate from Chainlink with a staleness check.
     *
     * @return price     The latest price (8 decimals for FX feeds)
     * @return updatedAt Timestamp of the last update
     *
     * @dev Reverts with a custom error if the feed has not been updated
     *      within STALENESS_THRESHOLD or returns a non-positive value.
     *
     *      Expected feed: JPY/USD (returns USD per 1 JPY, 8 decimals).
     */
    function getLatestRate()
        public
        view
        returns (int256 price, uint256 updatedAt)
    {
        (, price, , updatedAt, ) = priceFeed.latestRoundData();

        if (price <= 0) {
            revert InvalidOraclePrice(price);
        }
        if (block.timestamp - updatedAt >= STALENESS_THRESHOLD) {
            revert StalePriceFeed(block.timestamp, updatedAt, STALENESS_THRESHOLD);
        }
    }

    // ================================================================
    //  ADMIN FUNCTIONS
    // ================================================================

    /**
     * @notice Whitelist a student and map their hashed ID to their wallet.
     * @param student     Wallet address of the student
     * @param studentHash keccak256(abi.encodePacked(studentId)) — computed
     *                    off-chain so plaintext ID never touches the chain.
     *
     * @dev    Guards against both duplicate hash AND duplicate wallet.
     *         Without the wallet check, calling whitelistStudent(alice, hashB)
     *         after whitelistStudent(alice, hashA) would orphan hashA in the
     *         studentHashToWallet mapping.
     */
    function whitelistStudent(address student, bytes32 studentHash)
        external
        onlyRole(ADMIN_ROLE)
    {
        if (student == address(0))                          revert ZeroAddress();
        if (studentHash == bytes32(0))                      revert ZeroHash();
        if (studentHashToWallet[studentHash] != address(0)) revert HashAlreadyRegistered(studentHash);
        if (walletToStudentHash[student] != bytes32(0))     revert WalletAlreadyRegistered(student);

        _grantRole(STUDENT_ROLE, student);
        studentHashToWallet[studentHash] = student;
        walletToStudentHash[student] = studentHash;

        emit StudentWhitelisted(student, studentHash);
    }

    /**
     * @notice Batch-whitelist multiple students in a single transaction.
     *
     * @dev    Gas savings: pays the 21 000 base transaction gas only once.
     *         Uses calldata arrays and unchecked loop increment. Bounded
     *         by MAX_BATCH_SIZE. Includes both hash and wallet duplicate guards.
     *
     * @param students Array of student wallet addresses
     * @param hashes   Parallel array of keccak256 hashes of student IDs
     */
    function batchWhitelist(
        address[] calldata students,
        bytes32[] calldata hashes
    )
        external
        onlyRole(ADMIN_ROLE)
    {
        if (students.length != hashes.length) revert ArrayLengthMismatch();
        if (students.length == 0)             revert EmptyArray();
        if (students.length > MAX_BATCH_SIZE) revert BatchTooLarge(students.length);

        for (uint256 i = 0; i < students.length; ) {
            address student = students[i];
            bytes32 studentHash = hashes[i];

            if (student == address(0))                          revert ZeroAddress();
            if (studentHash == bytes32(0))                      revert ZeroHash();
            if (studentHashToWallet[studentHash] != address(0)) revert HashAlreadyRegistered(studentHash);
            if (walletToStudentHash[student] != bytes32(0))     revert WalletAlreadyRegistered(student);

            _grantRole(STUDENT_ROLE, student);
            studentHashToWallet[studentHash] = student;
            walletToStudentHash[student] = studentHash;

            emit StudentWhitelisted(student, studentHash);

            unchecked { ++i; }
        }
    }

    /**
     * @notice Remove a whitelisted student from the system.
     *         Revokes STUDENT_ROLE, clears credit units, payment status,
     *         hash mappings, and rate limiting state.
     *
     * @dev    Does NOT refund escrowed USDC — admin should call
     *         refundStudent() first if the student has a remaining
     *         escrow balance.
     *
     *         Also deletes lastDepositTime[student] to prevent stale
     *         cooldown state if the same wallet is re-whitelisted.
     *
     * @param student Wallet address of the student to remove
     */
    function removeStudent(address student)
        external
        onlyRole(ADMIN_ROLE)
    {
        if (!hasRole(STUDENT_ROLE, student)) revert StudentNotWhitelisted(student);

        // Retrieve and clear the hash mapping (both directions)
        bytes32 studentHash = walletToStudentHash[student];
        if (studentHash != bytes32(0)) {
            delete studentHashToWallet[studentHash];
            delete walletToStudentHash[student];
        }

        // Revoke role, clear ALL semester-specific and rate-limit data
        _revokeRole(STUDENT_ROLE, student);
        delete creditUnits[student];
        delete paymentCompleted[student];
        delete lastDepositTime[student];

        emit StudentRemoved(student, studentHash);
    }

    /**
     * @notice Assign credit units to a whitelisted student.
     * @param student Address of the student
     * @param units   Number of credit units (1–30)
     */
    function setCreditUnits(address student, uint256 units)
        external
        onlyRole(ADMIN_ROLE)
    {
        if (!hasRole(STUDENT_ROLE, student)) revert StudentNotWhitelisted(student);
        if (units < MIN_CREDIT_UNITS || units > MAX_CREDIT_UNITS) {
            revert CreditUnitsOutOfRange(units);
        }

        creditUnits[student] = units;
        emit CreditUnitsSet(student, units);
    }

    /**
     * @notice Batch-assign credit units to multiple whitelisted students
     *         in a single transaction.
     *
     * @dev    Gas savings: pays the 21 000 base transaction gas only once.
     *         Uses calldata arrays and unchecked loop increment. Bounded
     *         by MAX_BATCH_SIZE.
     *
     * @param students Array of student wallet addresses
     * @param units    Parallel array of credit unit values (1–30 each)
     */
    function batchSetCreditUnits(
        address[] calldata students,
        uint256[] calldata units
    )
        external
        onlyRole(ADMIN_ROLE)
    {
        if (students.length != units.length) revert ArrayLengthMismatch();
        if (students.length == 0)            revert EmptyArray();
        if (students.length > MAX_BATCH_SIZE) revert BatchTooLarge(students.length);

        for (uint256 i = 0; i < students.length; ) {
            address student = students[i];
            uint256 unitVal = units[i];

            if (!hasRole(STUDENT_ROLE, student)) revert StudentNotWhitelisted(student);
            if (unitVal < MIN_CREDIT_UNITS || unitVal > MAX_CREDIT_UNITS) {
                revert CreditUnitsOutOfRange(unitVal);
            }

            creditUnits[student] = unitVal;
            emit CreditUnitsSet(student, unitVal);

            unchecked { ++i; }
        }
    }

    /**
     * @notice Refund a student's full escrow balance without requiring
     *         the contract to be paused.
     *
     * @dev    CEI pattern: zero the balance (effect) before transferring
     *         (interaction). Only callable by admin.
     *
     * @param student Address of the student to refund
     */
    function refundStudent(address student)
        external
        onlyRole(ADMIN_ROLE)
        nonReentrant
    {
        uint256 balance = escrowBalance[student];
        if (balance == 0) revert NoFundsAvailable(student);

        // --- Effect (zero before transfer) ---
        escrowBalance[student] = 0;

        // --- Interaction ---
        if (!usdc.transfer(student, balance)) revert TransferFailed();

        emit Refund(student, balance);
    }

    /**
     * @notice Set the date when batch payment will be executed.
     * @param _date Unix timestamp for the payment deadline (must be future)
     *
     * @dev    Reverts if payments have already been executed this semester.
     *         Admin must call batchResetPayments first to reset semester
     *         state before setting a new payment date.
     */
    function setPaymentDate(uint256 _date)
        external
        onlyRole(ADMIN_ROLE)
    {
        if (_date <= block.timestamp)     revert PaymentDateMustBeFuture();
        if (paymentsExecutedThisSemester) revert PaymentsAlreadyExecuted();

        paymentDate = _date;
        emit PaymentDateSet(_date);
    }

    /**
     * @notice Update the university receiving wallet.
     * @param _newWallet New university wallet address
     */
    function setUniversityWallet(address _newWallet)
        external
        onlyRole(ADMIN_ROLE)
    {
        if (_newWallet == address(0)) revert ZeroAddress();
        address oldWallet = universityWallet;
        universityWallet = _newWallet;
        emit UniversityWalletUpdated(oldWallet, _newWallet);
    }

    /**
     * @notice Update the fee charged per credit unit.
     * @param _newFee New fee in USDC (6 decimals, must be > 0)
     *
     * @dev    Reverts if payments have already been executed this semester.
     *         Changing feePerUnit mid-semester would shift the deposit cap
     *         (calculateFees) for all students — those who deposited to the
     *         old cap would be silently underfunded or over-capped. Admin
     *         should configure fees before the deposit window opens.
     */
    function setFeePerUnit(uint256 _newFee)
        external
        onlyRole(ADMIN_ROLE)
    {
        if (_newFee == 0) revert FeesMustBePositive();
        if (paymentsExecutedThisSemester) revert PaymentsAlreadyExecuted();
        uint256 oldFee = feePerUnit;
        feePerUnit = _newFee;
        emit FeePerUnitUpdated(oldFee, _newFee);
    }

    /**
     * @notice Update the Chainlink price feed address.
     *
     * @dev    IMPORTANT: The new feed MUST be a JPY/USD feed (USD per 1 JPY).
     *         Plugging in a USD/JPY feed will invert all conversion math.
     *
     * @param _newFeed Address of the new AggregatorV3Interface contract
     */
    function setPriceFeed(address _newFeed)
        external
        onlyRole(ADMIN_ROLE)
    {
        if (_newFeed == address(0)) revert ZeroAddress();
        address oldFeed = address(priceFeed);
        priceFeed = AggregatorV3Interface(_newFeed);
        emit PriceFeedUpdated(oldFeed, _newFeed);
    }

    /**
     * @notice Lock the current FX rate for the semester.
     *         Reads getLatestRate() (which includes staleness check),
     *         then stores the rate so all students see the same JPY
     *         equivalent on their fee statements.
     *
     * @dev    Called once per semester by admin, typically before the
     *         payment window opens. The rate is safely cast from int256
     *         to uint256 — getLatestRate() reverts if price <= 0,
     *         guaranteeing the cast is safe.
     */
    function lockFxRate()
        external
        onlyRole(ADMIN_ROLE)
    {
        (int256 rate, ) = getLatestRate();

        // Safe cast: getLatestRate() reverts if rate <= 0
        uint256 positiveRate = uint256(rate);
        lockedFxRate = positiveRate;
        emit FxRateLocked(positiveRate, block.timestamp);
    }

    /**
     * @notice Clear the locked FX rate between semesters.
     *         Prevents stale rates from being silently reused if admin
     *         forgets to re-lock before the next payment cycle.
     *
     * @dev    After calling this, calculateFeesInJPY() and executePayment()
     *         will revert until lockFxRate() is called again, which is the
     *         desired fail-safe behaviour.
     */
    function resetLockedFxRate()
        external
        onlyRole(ADMIN_ROLE)
    {
        uint256 previousRate = lockedFxRate;
        lockedFxRate = 0;
        emit FxRateReset(previousRate);
    }

    /**
     * @notice Reset payment status for a batch of students at the start
     *         of a new semester. Also resets the paymentsExecutedThisSemester
     *         flag so setPaymentDate can be called for the new semester.
     *
     * @dev    Bounded by MAX_BATCH_SIZE. Only writes + emits for students
     *         whose paymentCompleted is currently true, avoiding wasted
     *         SSTORE gas (~2,900 per no-op write) and misleading events
     *         for students who were never paid.
     *
     * @param students Array of student addresses to reset
     */
    function batchResetPayments(address[] calldata students)
        external
        onlyRole(ADMIN_ROLE)
    {
        if (students.length == 0)             revert EmptyArray();
        if (students.length > MAX_BATCH_SIZE) revert BatchTooLarge(students.length);

        for (uint256 i = 0; i < students.length; ) {
            address student = students[i];
            if (!hasRole(STUDENT_ROLE, student)) revert StudentNotWhitelisted(student);

            // Only write + emit if actually paid (avoids wasted SSTORE + misleading event)
            if (paymentCompleted[student]) {
                paymentCompleted[student] = false;
                emit PaymentStatusReset(student);
            }

            unchecked { ++i; }
        }

        // Reset semester flag so setPaymentDate can be called again
        paymentsExecutedThisSemester = false;
    }

    /**
     * @notice Execute batch tuition payment from student escrow to university.
     *         Follows CEI (Checks-Effects-Interactions) per student.
     *
     * @dev Gas optimisations applied:
     *      - Bounded batch size prevents out-of-gas on large arrays
     *      - feePerUnit cached in memory to avoid repeated SLOAD
     *      - Unchecked loop increment (cannot overflow with bounded size)
     *      - FX rate fetched once and recorded in each payment event
     *
     *      Skips students with 0 credit units (required == 0) to prevent
     *      marking them as "paid" and emitting a phantom PaymentExecuted
     *      event for 0 USDC.
     *
     * @param students Array of student addresses to process (max 50)
     */
    function executePayment(address[] calldata students)
        external
        onlyRole(ADMIN_ROLE)
        nonReentrant
        whenNotPaused
    {
        // --- Checks ---
        if (paymentDate == 0)                  revert PaymentDateNotSet();
        if (block.timestamp < paymentDate)     revert PaymentDateNotReached(paymentDate, block.timestamp);
        if (students.length == 0)              revert EmptyArray();
        if (students.length > MAX_BATCH_SIZE)  revert BatchTooLarge(students.length);

        // Use the locked FX rate (set by admin for this semester)
        uint256 fxRate = lockedFxRate;
        if (fxRate == 0) revert FxRateNotLocked();

        // Cache storage variables to save gas (avoid repeated SLOAD)
        uint256 _feePerUnit = feePerUnit;
        address _universityWallet = universityWallet;

        // Mark that payments have been executed this semester
        paymentsExecutedThisSemester = true;

        for (uint256 i = 0; i < students.length; ) {
            address student = students[i];
            uint256 required = creditUnits[student] * _feePerUnit;
            uint256 balance  = escrowBalance[student];

            // Skip students with 0 credit units (prevents phantom 0-USDC payments)
            if (required == 0) {
                unchecked { ++i; }
                continue;
            }

            if (balance >= required && !paymentCompleted[student]) {
                // --- Effect (before interaction) ---
                escrowBalance[student] = balance - required;
                paymentCompleted[student] = true;

                // --- Interaction ---
                if (!usdc.transfer(_universityWallet, required)) revert TransferFailed();

                emit PaymentExecuted(student, required, fxRate, block.timestamp);
            } else if (paymentCompleted[student]) {
                // Already paid this semester — skip silently
            } else {
                emit InsufficientBalance(student, required, balance);
            }

            // Gas-optimised increment: safe because i < students.length <= 50
            unchecked { ++i; }
        }
    }

    /**
     * @notice Pause the contract. Disables deposits and payment execution.
     *         Enables emergencyWithdraw() for students to reclaim funds.
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause the contract. Re-enables normal operations.
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    // ================================================================
    //  STUDENT FUNCTIONS
    // ================================================================

    /**
     * @notice Deposit USDC into the student's escrow account.
     *         Student must first call usdc.approve(thisContract, amount).
     *
     * @dev    CEI pattern: update escrow balance (effect) BEFORE calling
     *         transferFrom (interaction).
     *
     *         Rate limiting: enforces DEPOSIT_COOLDOWN between successive
     *         deposits from the same wallet. Uses a custom error
     *         (DepositCooldownActive) to return the exact timestamp when
     *         the next deposit is allowed, enabling the frontend to display
     *         a countdown timer.
     *
     *         Deposit cap: the student's new escrow balance after deposit
     *         cannot exceed their calculated fees (creditUnits * feePerUnit).
     *         Prevents accidental over-deposits from a compromised key or
     *         frontend bug. Students who need to deposit the exact amount
     *         can call calculateFees() first to check.
     *
     * @param amount  USDC amount in 6-decimal units
     *                (e.g. 1000 USDC = 1000 * 10**6 = 1_000_000_000)
     */
    function deposit(uint256 amount)
        external
        onlyRole(STUDENT_ROLE)
        nonReentrant
        whenNotPaused
    {
        if (amount == 0) revert ZeroAmount();

        // --- Rate limiting check ---
        uint256 nextAllowed = lastDepositTime[msg.sender] + DEPOSIT_COOLDOWN;
        if (block.timestamp < nextAllowed) {
            revert DepositCooldownActive(msg.sender, nextAllowed);
        }

        // --- Deposit cap check ---
        uint256 maxAllowed = calculateFees(msg.sender);
        uint256 newBalance = escrowBalance[msg.sender] + amount;
        if (newBalance > maxAllowed) {
            revert DepositExceedsFees(msg.sender, newBalance, maxAllowed);
        }

        // --- Effects (update state before external call) ---
        lastDepositTime[msg.sender] = block.timestamp;
        escrowBalance[msg.sender] = newBalance;

        // --- Interaction (pull USDC from student wallet) ---
        if (!usdc.transferFrom(msg.sender, address(this), amount)) revert TransferFailed();

        emit Deposit(msg.sender, amount);
    }

    // ================================================================
    //  VIEW FUNCTIONS
    // ================================================================

    /**
     * @notice Calculate total fees owed by a student.
     * @param student  Address of the student
     * @return Total USDC owed (creditUnits * feePerUnit)
     */
    function calculateFees(address student) public view returns (uint256) {
        return creditUnits[student] * feePerUnit;
    }

    /**
     * @notice Convert a student's USDC fees to JPY using the locked FX rate.
     *         For frontend display only.
     *
     * @param student  Address of the student
     * @return JPY equivalent (whole yen, e.g. 150000 = ¥150,000)
     *
     * @dev    USDC uses 6 decimals, Chainlink JPY/USD feed uses 8 decimals.
     *
     *         The feed returns "USD per 1 JPY". For example, if 1 JPY = 0.00670000 USD,
     *         the feed returns 670000 (at 8 decimals).
     *
     *         To convert USDC → JPY:
     *           jpyAmount = (totalUsdc * 1e8) / (rate * 1e6)
     *
     *         Example: 1000 USDC (= 1_000_000_000 raw) at rate 670000:
     *           (1_000_000_000 * 1e8) / (670000 * 1e6) = 149,253 ≈ ¥149,253
     */
    function calculateFeesInJPY(address student) external view returns (uint256) {
        if (lockedFxRate == 0) revert FxRateNotLocked();
        uint256 totalUsdc = creditUnits[student] * feePerUnit;
        return (totalUsdc * 1e8) / (lockedFxRate * 1e6);
    }

    /**
     * @notice Return a student's combined status in a single call.
     *         Designed for frontend consumption — avoids multiple RPC
     *         round-trips to determine the student's lifecycle stage.
     *
     * @param student              Address of the student to query
     * @return isWhitelisted       True if the student holds STUDENT_ROLE
     * @return isDeposited         True if escrow balance >= total fees owed
     * @return isPaid              True if payment has been executed this semester
     * @return balance             Current escrow balance (USDC, 6 decimals)
     * @return nextDepositAllowed  Timestamp when the student can next call deposit()
     */
    function getStatus(address student)
        external
        view
        returns (
            bool isWhitelisted,
            bool isDeposited,
            bool isPaid,
            uint256 balance,
            uint256 nextDepositAllowed
        )
    {
        isWhitelisted = hasRole(STUDENT_ROLE, student);
        balance = escrowBalance[student];
        isDeposited = isWhitelisted && balance >= calculateFees(student);
        isPaid = paymentCompleted[student];
        nextDepositAllowed = lastDepositTime[student] + DEPOSIT_COOLDOWN;
    }

    /**
     * @notice Emergency withdrawal — student can reclaim their full escrow
     *         balance, but ONLY when the contract is paused (oracle failure,
     *         stablecoin depeg, detected exploit).
     *
     * @dev    CEI pattern: zero the balance (effect) before transferring
     *         (interaction). If transfer fails, the entire tx reverts.
     *
     *         Note: emergencyWithdraw is NOT rate-limited. When the contract
     *         is paused, the priority is allowing students to recover funds
     *         as quickly as possible.
     */
    function emergencyWithdraw()
        external
        nonReentrant
        whenPaused
    {
        uint256 balance = escrowBalance[msg.sender];
        if (balance == 0) revert NoFundsAvailable(msg.sender);

        // --- Effect (zero before transfer) ---
        escrowBalance[msg.sender] = 0;

        // --- Interaction ---
        if (!usdc.transfer(msg.sender, balance)) revert TransferFailed();

        emit EmergencyWithdrawal(msg.sender, balance);
    }
}
