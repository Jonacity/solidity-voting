// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract Voting is Ownable {
    enum WorkflowStatus {
        RegisteringVoters,
        ProposalsRegistrationStarted,
        ProposalsRegistrationEnded,
        VotingSessionStarted,
        VotingSessionEnded,
        VotesTallied
    }
    struct Voter {
        bool isRegistered;
        bool hasVoted;
        uint votedProposalId;
    }
    struct Proposal {
        uint id;
        string description;
        uint voteCount;
    }

    uint lastProposalId;
    uint winningProposalId;
    uint[] winningProposalIds;
    address[] voters;
    mapping(address => Voter) whitelist;
    mapping(uint => Proposal) proposals;
    Proposal[] proposalsList;
    WorkflowStatus public status;

    event VoterRegistered(address voterAddress);
    event WorkflowStatusChange(WorkflowStatus previousStatus, WorkflowStatus newStatus);
    event ProposalRegistered(uint proposalId);
    event Voted (address voter, uint proposalId);
    event Winned(string description);
    event ResetVote(uint date);

    modifier isRegistered {
        require(whitelist[msg.sender].isRegistered == true, "You are not registred");
        _;
    }

    modifier isValidId(uint _id) {
        require(_id > 0 && _id <= lastProposalId, "Invalid proposal id");
        _;
    }

    modifier canRemoveProposal {
        require(status == WorkflowStatus.ProposalsRegistrationStarted, "Invalid status to remove a proposal");
        _;
    }

    modifier isVoteEnded {
        require(status == WorkflowStatus.VotesTallied, "Votes not tallied");
        _;
    }

    function registrerVoter(address _address) external onlyOwner returns(bool) {
        require(status == WorkflowStatus.RegisteringVoters, "You cannot registrer voters");
        require(whitelist[_address].isRegistered == false, "Voter already registred");

        whitelist[_address] = Voter(true, false, 0);
        voters.push(_address);
        emit VoterRegistered(_address);
        return true;
    }

    function setNewStatus(WorkflowStatus _newStatus) internal {
        status = _newStatus;
        emit WorkflowStatusChange(status, _newStatus);
    }

    /**
      * This function is called by the admin to follow the voting workflow
      * @dev The status variable tracks the current step
      */
    function goToNextStep() external onlyOwner {
        if (status == WorkflowStatus.RegisteringVoters) {
            require(voters.length > 0, "No voters registrered");

            setNewStatus(WorkflowStatus.ProposalsRegistrationStarted);
        } else if (status == WorkflowStatus.ProposalsRegistrationStarted) {
            require(proposalsList.length > 0, "No proposals registred");

            setNewStatus(WorkflowStatus.ProposalsRegistrationEnded);
        } else if (status == WorkflowStatus.ProposalsRegistrationEnded) {
            setNewStatus(WorkflowStatus.VotingSessionStarted);
        } else if (status == WorkflowStatus.VotingSessionStarted) {
            require(hasOneVote() == true, "No votes during the session");

            setNewStatus(WorkflowStatus.VotingSessionEnded);
        } else if (status == WorkflowStatus.VotingSessionEnded) {
            setWinningProposalId();
            require(areMultipleWinners() == false, string(bytes.concat(bytes("There are "), bytes(Strings.toString(winningProposalIds.length)), bytes(" winners"))));

            setNewStatus(WorkflowStatus.VotesTallied);
            emit Winned(proposals[winningProposalId].description);
        } else if (status == WorkflowStatus.VotesTallied) {
            resetVote();
        }
    }

    function hasOneVote() internal view returns(bool) {
        for (uint n = 0; n < proposalsList.length; n ++) {
            if (proposalsList[n].voteCount > 0) {
                return true;
            }
        }
        return false;
    }

    function addProposal(string memory _description) external isRegistered {
        require(status == WorkflowStatus.ProposalsRegistrationStarted, "You cannot registrer proposals");
        require(keccak256(abi.encode(_description)) != keccak256(abi.encode("")), "You cannot add an empty proposal");

        lastProposalId ++;
        Proposal memory proposal = Proposal(lastProposalId, _description, 0);
        proposalsList.push(proposal);
        proposals[lastProposalId] = proposal;
        emit ProposalRegistered(lastProposalId);
    }

    function removeLastProposal() external onlyOwner canRemoveProposal {
        delete proposals[lastProposalId];
        proposalsList.pop();
    }

    function listProposals() external view returns(Proposal[] memory) {
        return proposalsList;
    }

    function showVote(address _address) external view isRegistered isVoteEnded returns(string memory) {
        require(whitelist[_address].votedProposalId != 0, "This user has not voted");

        return proposals[whitelist[_address].votedProposalId].description;
    }

    function voteFor(uint _proposalId) external isRegistered isValidId(_proposalId) {
        require(status == WorkflowStatus.VotingSessionStarted, "You cannot vote for now");
        require(whitelist[msg.sender].hasVoted == false, "You have already voted");

        whitelist[msg.sender].hasVoted = true;
        whitelist[msg.sender].votedProposalId = _proposalId;
        proposals[_proposalId].voteCount ++;
        for (uint n = 0; n < proposalsList.length; n ++) {
            if (proposalsList[n].id == _proposalId) {
                proposalsList[n].voteCount ++;
                break;
            }
        }
        emit Voted(msg.sender, _proposalId);
    }

    function setWinningProposalId() internal {
        uint winningVoteCount;
        uint tempWinningProposalId;
        for (uint n = 0; n < proposalsList.length; n ++) {
            if (proposalsList[n].voteCount > winningVoteCount) {
                winningVoteCount = proposalsList[n].voteCount;
                tempWinningProposalId = proposalsList[n].id;
            }
        }
        winningProposalId = tempWinningProposalId;
    }

    function areMultipleWinners() internal returns(bool) {
        if (proposalsList.length < 2) {
            return false;
        }
        uint winningVoteCount = proposals[winningProposalId].voteCount;
        for (uint n = 0; n < proposalsList.length; n ++) {
            if (proposalsList[n].voteCount == winningVoteCount) {
                winningProposalIds.push(proposalsList[n].id);
            }
        }
        return winningProposalIds.length > 1;
    }

    function getWinner() external view isVoteEnded returns(string memory winnerName) {
        return winnerName = proposals[winningProposalId].description;
    }

    function resetVote() public onlyOwner returns(bool) {
        for (uint n = 0; n < voters.length; n ++) {
            delete whitelist[voters[n]];
        }
        for (uint n = 0; n < proposalsList.length; n ++) {
            delete proposals[proposalsList[n].id];
        }
        delete voters;
        delete proposalsList;
        lastProposalId = 0;
        winningProposalId = 0;
        status = WorkflowStatus.RegisteringVoters;
        emit ResetVote(block.timestamp);
        return true;
    }
}
