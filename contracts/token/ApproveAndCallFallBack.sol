pragma solidity ^0.5.3;

contract ApproveAndCallFallBack {
  function receiveApproval(address from, uint256 _amount, address _token, bytes memory _data) public;
}
