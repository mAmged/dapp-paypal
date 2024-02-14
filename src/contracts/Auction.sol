// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title Auction Contract for Daltonic Tokens (DAT)
 * @dev This contract allows users to create and manage NFT auctions.
 */
contract Auction is ERC721URIStorage, ReentrancyGuard {
    using Counters for Counters.Counter;
    Counters.Counter private totalItems;

    address public companyAcc; // Address of the company account
    uint256 public listingPrice = 0.02 ether; // Listing price for creating an auction
    uint256 public royaltyFee; // Royalty fee percentage
    mapping(uint256 => AuctionStruct) public auctionedItem; // Mapping of auctioned items
    mapping(uint256 => bool) public auctionedItemExist; // Mapping to check if an item exists
    mapping(string => uint256) public existingURIs; // Mapping to track existing URIs
    mapping(uint256 => BidderStruct[]) public biddersOf; // Mapping of bidders for each item

    constructor(uint256 _royaltyFee) ERC721("Daltonic Tokens", "DAT") {
        companyAcc = msg.sender;
        royaltyFee = _royaltyFee;
    }

    struct BidderStruct {
        address bidder; // Address of the bidder
        uint256 price; // Bid price
        uint256 timestamp; // Timestamp of the bid
        bool refunded; // Flag indicating if the bid was refunded
        bool won; // Flag indicating if the bidder won the auction
    }

    struct AuctionStruct {
        string name; // Name of the auctioned item
        string description; // Description of the item
        string image; // URI of the item's image
        uint256 tokenId; // Token ID of the NFT
        address seller; // Address of the seller
        address owner; // Current owner of the NFT
        address winner; // Address of the winning bidder
        uint256 price; // Current auction price
        bool sold; // Flag indicating if the item is sold
        bool live; // Flag indicating if the auction is active
        bool biddable; // Flag indicating if the item is biddable
        uint256 bids; // Number of bids received
        uint256 duration; // Duration of the auction
    }

    event AuctionItemCreated(
        uint256 indexed tokenId,
        address seller,
        address owner,
        uint256 price,
        bool sold
    );

    /**
     * @dev Returns the listing price for creating an auction.
     * @return The listing price in wei.
     */
    function getListingPrice() external view returns (uint256) {
        return listingPrice;
    }

    /**
     * @dev Sets the listing price for creating an auction.
     * @param _price The new listing price in wei.
     */
    function setListingPrice(uint256 _price) external {
        require(msg.sender == companyAcc, "Unauthorized entity");
        listingPrice = _price;
    }

    /**
     * @dev Changes the price of an auctioned item.
     * @param tokenId The token ID of the auctioned item.
     * @param price The new price in wei.
     */
    function changePrice(uint256 tokenId, uint256 price) external {
        require(
            auctionedItem[tokenId].owner == msg.sender,
            "Unauthorized entity"
        );
        require(
            getTimestamp(0, 0, 0, 0) > auctionedItem[tokenId].duration,
            "Auction still live"
        );
        require(price > 0 ether, "Price must be greater than zero");

        auctionedItem[tokenId].price = price;
    }

    /**
     * @dev Mints a new token and associates it with the given token URI.
     * @param tokenURI The URI for the token's metadata.
     * @return A boolean indicating whether the minting was successful.
     */
    function mintToken(string memory tokenURI) internal returns (bool) {
        totalItems.increment();
        uint256 tokenId = totalItems.current();

        _mint(msg.sender, tokenId);
        _setTokenURI(tokenId, tokenURI);

        return true;
    }

    /**
     * @dev Creates a new auction for an NFT.
     * @param name The name of the auctioned item.
     * @param description The description of the item.
     * @param image The URI of the item's image.
     * @param tokenURI The URI for the token's metadata.
     * @param price The initial auction price in wei.
     */
    function createAuction(
        string memory name,
        string memory description,
        string memory image,
        string memory tokenURI,
        uint256 price
    ) public payable nonReentrant {
        require(price > 0 ether, "Sales price must be greater than 0 ethers.");
        require(
            msg.value >= listingPrice,
            "Price must be up to the listing price."
        );
        require(mintToken(tokenURI), "Could not mint token");

        uint256 tokenId = totalItems.current();

        AuctionStruct memory item;
        item.tokenId = tokenId;
        item.name = name;
        item.description = description;
        item.image = image;
        item.price = price;
        item.duration = getTimestamp(0, 0, 0, 0);
        item.seller = msg.sender;
        item.owner = msg.sender;

        auctionedItem[tokenId] = item;
        auctionedItemExist[tokenId] = true;

        payTo(companyAcc, listingPrice);

        emit AuctionItemCreated(tokenId, msg.sender, address(0), price, false);
    }

    /**
     * @dev Places a bid in an ongoing auction.
     * @param tokenId The token ID of the auctioned item.
     */
    function placeBid(uint256 tokenId) public payable {
        require(
            msg.value >= auctionedItem[tokenId].price,
            "Insufficient amount"
        );
        require(
            auctionedItem[tokenId].duration > (0, 0, 0, 0),
            "Auction not available"
        );
        require(auctionedItem[tokenId].biddable, "Auction only for bidding");

        BidderStruct memory bidder;
        bidder.bidder = msg.sender;
        bidder.price = msg.value;
        bidder.timestamp = getTimestamp(0,        0, 0, 0, 0);

        biddersOf[tokenId].push(bidder);
        auctionedItem[tokenId].bids++;
        auctionedItem[tokenId].price = msg.value;
        auctionedItem[tokenId].winner = msg.sender;
    }

    /**
     * @dev Claims the prize for the winning bidder after the auction has ended.
     * @param tokenId The token ID of the auctioned item.
     * @param bid The index of the winning bid.
     */
    function claimPrize(uint256 tokenId, uint256 bid) public {
        require(
            getTimestamp(0, 0, 0, 0) > auctionedItem[tokenId].duration,
            "Auction still live"
        );
        require(
            auctionedItem[tokenId].winner == msg.sender,
            "You are not the winner"
        );

        // Mark the winning bidder
        biddersOf[tokenId][bid].won = true;

        uint256 price = auctionedItem[tokenId].price;
        address seller = auctionedItem[tokenId].seller;

        // Reset auction parameters
        auctionedItem[tokenId].winner = address(0);
        auctionedItem[tokenId].live = false;
        auctionedItem[tokenId].sold = true;
        auctionedItem[tokenId].bids = 0;
        auctionedItem[tokenId].duration = getTimestamp(0, 0, 0, 0);

        // Calculate royalty fee
        uint256 royalty = (price * royaltyFee) / 100;

        // Distribute funds
        payTo(auctionedItem[tokenId].owner, (price - royalty));
        payTo(seller, royalty);

        // Transfer NFT ownership to the winner
        IERC721(address(this)).transferFrom(address(this), msg.sender, tokenId);
        auctionedItem[tokenId].owner = msg.sender;

        // Perform refunds for other bidders
        performRefund(tokenId);
    }

    /**
     * @dev Performs refunds for non-winning bidders.
     * @param tokenId The token ID of the auctioned item.
     */
    function performRefund(uint256 tokenId) internal {
        for (uint256 i = 0; i < biddersOf[tokenId].length; i++) {
            if (biddersOf[tokenId][i].bidder != msg.sender) {
                biddersOf[tokenId][i].refunded = true;
                payTo(biddersOf[tokenId][i].bidder, biddersOf[tokenId][i].price);
            } else {
                biddersOf[tokenId][i].won = true;
            }
            biddersOf[tokenId][i].timestamp = getTimestamp(0, 0, 0, 0);
        }

        // Clear the list of bidders
        delete biddersOf[tokenId];
    }

    /**
     * @dev Returns unsold auctions.
     * @return Auctions An array of unsold auction items.
     */
    function getUnsoldAuction() public view returns (AuctionStruct[] memory) {
        uint256 totalItemsCount = totalItems.current();
        uint256 totalSpace;
        for (uint256 i = 0; i < totalItemsCount; i++) {
            if (!auctionedItem[i + 1].sold) {
                totalSpace++;
            }
        }

        AuctionStruct[] memory Auctions = new AuctionStruct;

        uint256 index;
        for (uint256 i = 0; i < totalItemsCount; i++) {
            if (!auctionedItem[i + 1].sold) {
                Auctions[index] = auctionedItem[i + 1];
                index++;
            }
        }

        return Auctions;
    }

    /**
     * @dev Returns auctions owned by the caller.
     * @return Auctions An array of auction items owned by the caller.
     */
    function getMyAuctions() public view returns (AuctionStruct[] memory) {
        uint256 totalItemsCount = totalItems.current();
        uint256 totalSpace;
        for (uint256 i = 0; i < totalItemsCount; i++) {
            if (auctionedItem[i + 1].owner == msg.sender) {
                totalSpace++;
            }
        }

        AuctionStruct[] memory Auctions = new AuctionStruct;

        uint256 index;
        for (uint256 i = 0; i < totalItemsCount; i++) {
            if (auctionedItem[i + 1].owner == msg.sender) {
                Auctions[index] = auctionedItem[i + 1];
                index++;
            }
        }

        return Auctions;
    }

    /**
     * @dev Returns sold auctions.
     * @return Auctions An array of sold auction items.
     */
    function getSoldAuction() public view returns (AuctionStruct[] memory) {
        uint256 totalItemsCount = totalItems.current();
        uint256 totalSpace;
        for (uint256 i = 0; i < totalItemsCount; i++) {
            if (auctionedItem[i + 1].sold) {
                totalSpace++;
            }
        }

        AuctionStruct[] memory Auctions = new AuctionStruct;

        uint256 index;
        for (uint256 i = 0; i < totalItemsCount; i++) {
            if (auctionedItem[i + 1].sold) {
                Auctions[index] = auctionedItem[i + 1];
                index++;
            }
        }

        return Auctions;
    }

    /**
     * @dev Returns live auctions.
     * @return Auctions An array of live auction items.
     */
    function getLiveAuctions() public view returns (AuctionStruct[] memory) {
        uint256 totalItemsCount = totalItems.current();
        uint256 totalSpace;
        for (uint256 i = 0; i < totalItemsCount; i++) {
            if (auctionedItem[i + 1].duration > getTimestamp(0, 0, 0, 0)) {
                totalSpace++;
            }
        }

        AuctionStruct[] memory Auctions = new AuctionStruct;

        uint256 index;
        for (uint256 i = 0; i < totalItemsCount; i++) {
            if (auctionedItem[i + 1].duration > getTimestamp(0, 0, 0, 0)) {
                Auctions[index] = auctionedItem[i + 1];
                index++;
            }
        }

        return Auctions;
    }

    /**
     * @dev Returns the bidders for a specific auction.
     * @param tokenId The token ID of the auctioned item.
     * @return bidders An array of bidder information.
     */
    function getBidders(uint256 tokenId)
        public
        view
        returns (BidderStruct[] memory)
    {
        return biddersOf[tokenId];
    }

    /**
     * @dev Converts time units to a timestamp.
     * @param sec The duration in seconds.
     * @param min The duration in minutes.
     * @param hour The duration in hours.
     * @param day The duration in days.
     * @return The calculated timestamp.
     */
    function getTimestamp(
        uint256 sec,
        uint256 min,
        uint256 hour,
        uint256 day
    ) internal view returns (uint256) {
        return
            block.timestamp +
            (1 seconds * sec) +
            (1 minutes * min) +
            (1 hours * hour) +
            (1 days * day);
    }

    /**
     * @dev Sends funds to the specified address.
     * @param to The recipient address.
     * @param amount The amount to send in wei.
     */
    function payTo(address to, uint256 amount) internal {
        (bool success, ) = payable(to).call{value: amount}("");
        require(success, "Payment failed");
    }
}
