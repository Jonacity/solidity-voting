// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";

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
    address[] voters;
    mapping(address => Voter) whitelist;
    mapping(uint => Proposal) proposals;
    Proposal[] proposalsList;
    WorkflowStatus public status;

    event VoterRegistered(address voterAddress); 
    event WorkflowStatusChange(WorkflowStatus previousStatus, WorkflowStatus newStatus);
    event ProposalRegistered(uint proposalId);
    event ProposalRemoved(uint proposalId);
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
            emit WorkflowStatusChange(status, _newStatus);
            status = _newStatus;
    }

    /**
      * This function is called by the admin to follow the voting workflow
      * @dev The status variable tracks the current step
      */
    function proceedToNextStep() external onlyOwner returns(string memory message) {
        if (status == WorkflowStatus.RegisteringVoters) {
            setNewStatus(WorkflowStatus.ProposalsRegistrationStarted);
            return message = "Start proposals registration...";
        } else if (status == WorkflowStatus.ProposalsRegistrationStarted) {
            setNewStatus(WorkflowStatus.ProposalsRegistrationEnded);
            return message = "Proposals registration ended";
        } else if (status == WorkflowStatus.ProposalsRegistrationEnded) {
            setNewStatus(WorkflowStatus.VotingSessionStarted);
            return message = "Start voting...";
        } else if (status == WorkflowStatus.VotingSessionStarted) {
            setNewStatus(WorkflowStatus.VotingSessionEnded);
            return message = "Voting session ended";
        } else if (status == WorkflowStatus.VotingSessionEnded) {
            setWinningProposalId();
            setNewStatus(WorkflowStatus.VotesTallied);
            emit Winned(proposals[winningProposalId].description);
            return message = "Votes tallied";
        }
    }

    function addProposal(string memory _description) external isRegistered returns(bool) {
        require(status == WorkflowStatus.ProposalsRegistrationStarted, "You cannot registrer proposals");
    
        lastProposalId ++;
        Proposal memory proposal = Proposal(lastProposalId, _description, 0);
        proposalsList.push(proposal);
        proposals[lastProposalId] = proposal;
        emit ProposalRegistered(lastProposalId);
        return true;
    }

    function removeLastProposal() external onlyOwner canRemoveProposal returns(bool) {
        emit ProposalRemoved(lastProposalId);
        delete proposals[lastProposalId];
        proposalsList.pop();
        return true;
    }

    function removeProposal(uint _proposalId) external onlyOwner canRemoveProposal isValidId(_proposalId) returns(bool) {
        emit ProposalRemoved(_proposalId);
        delete proposalsList[_proposalId - 1];
        delete proposals[_proposalId];
        return true;
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

        Voter storage sender = whitelist[msg.sender];
        sender.hasVoted = true;
        sender.votedProposalId = _proposalId;
        proposals[_proposalId].voteCount ++;
        for (uint n = 0; n < proposalsList.length; n ++) {
            if (proposalsList[n].id == _proposalId) {
                proposalsList[n].voteCount ++;
            }
        }
        emit Voted(msg.sender, _proposalId);
    }

    function setWinningProposalId() internal {
        uint winningVoteCount;
        for (uint n = 0; n < proposalsList.length; n ++) {
            if (proposalsList[n].voteCount > winningVoteCount) {
                winningVoteCount = proposalsList[n].voteCount;
                winningProposalId = proposalsList[n].id;
            }
        }
    }

    function getWinner() external view isVoteEnded returns(string memory winnerName) {
        return winnerName = proposals[winningProposalId].description;
    }

    function resetVote() external onlyOwner isVoteEnded returns(bool) {
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
