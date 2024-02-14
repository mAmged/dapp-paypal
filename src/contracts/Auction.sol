// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Auction is ERC721URIStorage, ReentrancyGuard {
    using Counters for Counters.Counter;
    Counters.Counter private totalItems;

    address public companyAcc;
    uint256 public listingPrice = 0.02 ether;
    uint256 public royaltyFee;
    mapping(uint256 => AuctionStruct) public auctionedItem;
    mapping(uint256 => bool) public auctionedItemExist;
    mapping(string => uint256) public existingURIs;
    mapping(uint256 => BidderStruct[]) public biddersOf;

    constructor(uint256 _royaltyFee) ERC721("Daltonic Tokens", "DAT") {
        companyAcc = msg.sender;
        royaltyFee = _royaltyFee;
    }

    struct BidderStruct {
        address bidder;
        uint256 price;
        uint256 timestamp;
        bool refunded;
        bool won;
    }

    struct AuctionStruct {
        string name;
        string description;
        string image;
        uint256 tokenId;
        address seller;
        address owner;
        address winner;
        uint256 price;
        bool sold;
        bool live;
        bool biddable;
        uint256 bids;
        uint256 duration;
    }

    event AuctionItemCreated(
        uint256 indexed tokenId,
        address seller,
        address owner,
        uint256 price,
        bool sold
    );

    function getListingPrice() external view returns (uint256) {
        return listingPrice;
    }

    function setListingPrice(uint256 _price) external {
        require(msg.sender == companyAcc, "Unauthorized entity");
        listingPrice = _price;
    }

    function changePrice(uint256 tokenId, uint256 price) external {
        require(
            auctionedItem[tokenId].owner == msg.sender,
            "Unauthorized entity"
        );
        auctionedItem[tokenId].price = price;
    }
}
