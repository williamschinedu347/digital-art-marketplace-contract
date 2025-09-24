;; NFT Artwork Trading Smart Contract
;; Facilitates creation, trading, and management of NFT artworks on the marketplace

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-TOKEN-NOT-FOUND (err u301))
(define-constant ERR-NOT-OWNER (err u302))
(define-constant ERR-TOKEN-NOT-FOR-SALE (err u303))
(define-constant ERR-INSUFFICIENT-PAYMENT (err u304))
(define-constant ERR-INVALID-PRICE (err u305))
(define-constant ERR-INVALID-ROYALTY (err u306))
(define-constant ERR-ALREADY-LISTED (err u307))
(define-constant ERR-SELF-PURCHASE (err u308))
(define-constant ERR-INVALID-METADATA (err u309))

;; Contract constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant MAX-ROYALTY-BPS u1000) ;; 10% maximum royalty
(define-constant MARKETPLACE-FEE-BPS u250) ;; 2.5% marketplace fee
(define-constant MIN-PRICE u1000) ;; 1000 microSTX minimum
(define-constant MAX-PRICE u1000000000) ;; 1B microSTX maximum

;; NFT trait for SIP-009 compliance
(define-trait nft-trait
  (
    (get-last-token-id () (response uint uint))
    (get-token-uri (uint) (response (optional (string-ascii 256)) uint))
    (get-owner (uint) (response (optional principal) uint))
    (transfer (uint principal principal) (response bool uint))
  )
)

;; Data variables
(define-data-var next-token-id uint u1)
(define-data-var total-minted uint u0)
(define-data-var total-sales uint u0)
(define-data-var total-volume uint u0)
(define-data-var contract-balance uint u0)

;; Data maps
(define-map tokens
  uint
  {
    owner: principal,
    artist: principal,
    title: (string-ascii 100),
    description: (string-ascii 500),
    image-uri: (string-ascii 256),
    metadata-uri: (optional (string-ascii 256)),
    mint-time: uint,
    royalty-bps: uint,
    total-sales: uint,
    total-revenue: uint
  }
)

(define-map marketplace-listings
  uint
  {
    seller: principal,
    price: uint,
    list-time: uint,
    expires-at: (optional uint)
  }
)

(define-map sales-history
  { token-id: uint, sale-id: uint }
  {
    seller: principal,
    buyer: principal,
    price: uint,
    sale-time: uint,
    marketplace-fee: uint,
    royalty-fee: uint
  }
)

(define-map artist-profiles
  principal
  {
    name: (string-ascii 100),
    bio: (string-ascii 500),
    website: (optional (string-ascii 200)),
    verified: bool,
    total-artworks: uint,
    total-sales: uint,
    total-revenue: uint
  }
)

(define-map token-offers
  { token-id: uint, offer-id: uint }
  {
    offerer: principal,
    amount: uint,
    expires-at: uint,
    active: bool
  }
)

(define-map collection-stats
  principal
  {
    total-owned: uint,
    total-purchased: uint,
    total-sold: uint,
    total-spent: uint,
    total-earned: uint
  }
)

;; Authorization functions
(define-private (is-contract-owner)
  (is-eq tx-sender CONTRACT-OWNER)
)

(define-private (is-token-owner (token-id uint))
  (match (map-get? tokens token-id)
    token (is-eq tx-sender (get owner token))
    false
  )
)

;; Utility functions
(define-private (is-valid-price (price uint))
  (and (>= price MIN-PRICE)
       (<= price MAX-PRICE))
)

(define-private (is-valid-royalty (royalty-bps uint))
  (<= royalty-bps MAX-ROYALTY-BPS)
)

(define-private (calculate-fees (price uint) (royalty-bps uint))
  {
    marketplace-fee: (/ (* price MARKETPLACE-FEE-BPS) u10000),
    royalty-fee: (/ (* price royalty-bps) u10000)
  }
)

(define-private (get-current-block-height)
  block-height
)

;; Core NFT minting function
(define-public (mint-artwork (recipient principal)
                            (title (string-ascii 100))
                            (description (string-ascii 500))
                            (image-uri (string-ascii 256))
                            (metadata-uri (optional (string-ascii 256)))
                            (royalty-bps uint))
  (let (
    (token-id (var-get next-token-id))
    (current-height (get-current-block-height))
  )
    (asserts! (is-valid-royalty royalty-bps) ERR-INVALID-ROYALTY)
    (asserts! (> (len title) u0) ERR-INVALID-METADATA)
    (asserts! (> (len image-uri) u0) ERR-INVALID-METADATA)
    
    ;; Create token record
    (map-set tokens token-id {
      owner: recipient,
      artist: tx-sender,
      title: title,
      description: description,
      image-uri: image-uri,
      metadata-uri: metadata-uri,
      mint-time: current-height,
      royalty-bps: royalty-bps,
      total-sales: u0,
      total-revenue: u0
    })
    
    ;; Initialize or update artist profile
    (update-artist-profile tx-sender)
    
    ;; Initialize collector stats for recipient
    (update-collector-stats recipient u0 u0 u0 u0)
    
    ;; Update counters
    (var-set next-token-id (+ token-id u1))
    (var-set total-minted (+ (var-get total-minted) u1))
    
    (ok token-id)
  )
)

;; List artwork for sale
(define-public (list-for-sale (token-id uint) (price uint) (expires-in-blocks (optional uint)))
  (let (
    (token (unwrap! (map-get? tokens token-id) ERR-TOKEN-NOT-FOUND))
    (current-height (get-current-block-height))
    (expires-at (match expires-in-blocks
                  blocks (some (+ current-height blocks))
                  none))
  )
    (asserts! (is-token-owner token-id) ERR-NOT-OWNER)
    (asserts! (is-valid-price price) ERR-INVALID-PRICE)
    (asserts! (is-none (map-get? marketplace-listings token-id)) ERR-ALREADY-LISTED)
    
    ;; Create marketplace listing
    (map-set marketplace-listings token-id {
      seller: tx-sender,
      price: price,
      list-time: current-height,
      expires-at: expires-at
    })
    
    (ok true)
  )
)

;; Remove from marketplace
(define-public (unlist-artwork (token-id uint))
  (let (
    (listing (unwrap! (map-get? marketplace-listings token-id) ERR-TOKEN-NOT-FOR-SALE))
  )
    (asserts! (is-eq tx-sender (get seller listing)) ERR-NOT-AUTHORIZED)
    
    (map-delete marketplace-listings token-id)
    (ok true)
  )
)

;; Purchase artwork from marketplace
(define-public (purchase-artwork (token-id uint))
  (let (
    (token (unwrap! (map-get? tokens token-id) ERR-TOKEN-NOT-FOUND))
    (listing (unwrap! (map-get? marketplace-listings token-id) ERR-TOKEN-NOT-FOR-SALE))
    (current-height (get-current-block-height))
    (price (get price listing))
    (seller (get seller listing))
    (artist (get artist token))
    (fees (calculate-fees price (get royalty-bps token)))
  )
    (asserts! (not (is-eq tx-sender seller)) ERR-SELF-PURCHASE)
    
    ;; Check expiration
    (match (get expires-at listing)
      expires (asserts! (<= current-height expires) ERR-TOKEN-NOT-FOR-SALE)
      true
    )
    
    ;; Transfer payment
    (try! (stx-transfer? price tx-sender (as-contract tx-sender)))
    
    ;; Calculate and distribute payments
    (let (
      (marketplace-fee (get marketplace-fee fees))
      (royalty-fee (get royalty-fee fees))
      (seller-amount (- price (+ marketplace-fee royalty-fee)))
    )
      ;; Pay seller
      (try! (as-contract (stx-transfer? seller-amount tx-sender seller)))
      
      ;; Pay royalty to artist (if different from seller)
      (if (not (is-eq artist seller))
        (try! (as-contract (stx-transfer? royalty-fee tx-sender artist)))
        true
      )
      
      ;; Keep marketplace fee in contract
      (var-set contract-balance (+ (var-get contract-balance) marketplace-fee))
      
      ;; Transfer ownership
      (map-set tokens token-id (merge token {
        owner: tx-sender,
        total-sales: (+ (get total-sales token) u1),
        total-revenue: (+ (get total-revenue token) price)
      }))
      
      ;; Remove from marketplace
      (map-delete marketplace-listings token-id)
      
      ;; Record sale history
      (record-sale token-id seller tx-sender price marketplace-fee royalty-fee)
      
      ;; Update statistics
      (var-set total-sales (+ (var-get total-sales) u1))
      (var-set total-volume (+ (var-get total-volume) price))
      
      ;; Update collector stats
      (update-collector-stats seller u0 u0 u1 (get total-earned (default-to { total-owned: u0, total-purchased: u0, total-sold: u0, total-spent: u0, total-earned: u0 } (map-get? collection-stats seller))))
      (update-collector-stats tx-sender u1 u1 u0 price)
      
      (ok token-id)
    )
  )
)

;; Direct transfer between users
(define-public (transfer-artwork (token-id uint) (sender principal) (recipient principal))
  (let (
    (token (unwrap! (map-get? tokens token-id) ERR-TOKEN-NOT-FOUND))
  )
    (asserts! (is-eq tx-sender sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq sender (get owner token)) ERR-NOT-OWNER)
    
    ;; Remove from marketplace if listed
    (map-delete marketplace-listings token-id)
    
    ;; Transfer ownership
    (map-set tokens token-id (merge token {
      owner: recipient
    }))
    
    ;; Update collector stats
    (update-collector-stats sender u0 u0 u0 u0)
    (update-collector-stats recipient u1 u0 u0 u0)
    
    (ok true)
  )
)

;; Set or update royalty for owned token
(define-public (set-royalty (token-id uint) (new-royalty-bps uint))
  (let (
    (token (unwrap! (map-get? tokens token-id) ERR-TOKEN-NOT-FOUND))
  )
    (asserts! (is-eq tx-sender (get artist token)) ERR-NOT-AUTHORIZED)
    (asserts! (is-valid-royalty new-royalty-bps) ERR-INVALID-ROYALTY)
    
    (map-set tokens token-id (merge token {
      royalty-bps: new-royalty-bps
    }))
    
    (ok true)
  )
)

;; Make an offer on a token
(define-public (make-offer (token-id uint) (amount uint) (expires-in-blocks uint))
  (let (
    (token (unwrap! (map-get? tokens token-id) ERR-TOKEN-NOT-FOUND))
    (current-height (get-current-block-height))
    (offer-id (get-next-offer-id token-id))
  )
    (asserts! (is-valid-price amount) ERR-INVALID-PRICE)
    (asserts! (not (is-eq tx-sender (get owner token))) ERR-SELF-PURCHASE)
    
    ;; Lock the offer amount
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    ;; Create offer
    (map-set token-offers { token-id: token-id, offer-id: offer-id } {
      offerer: tx-sender,
      amount: amount,
      expires-at: (+ current-height expires-in-blocks),
      active: true
    })
    
    (ok offer-id)
  )
)

;; Accept an offer
(define-public (accept-offer (token-id uint) (offer-id uint))
  (let (
    (token (unwrap! (map-get? tokens token-id) ERR-TOKEN-NOT-FOUND))
    (offer (unwrap! (map-get? token-offers { token-id: token-id, offer-id: offer-id }) ERR-TOKEN-NOT-FOUND))
    (current-height (get-current-block-height))
  )
    (asserts! (is-token-owner token-id) ERR-NOT-OWNER)
    (asserts! (get active offer) ERR-TOKEN-NOT-FOUND)
    (asserts! (<= current-height (get expires-at offer)) ERR-TOKEN-NOT-FOUND)
    
    (let (
      (price (get amount offer))
      (buyer (get offerer offer))
      (artist (get artist token))
      (fees (calculate-fees price (get royalty-bps token)))
      (marketplace-fee (get marketplace-fee fees))
      (royalty-fee (get royalty-fee fees))
      (seller-amount (- price (+ marketplace-fee royalty-fee)))
    )
      ;; Transfer payments from locked funds
      (try! (as-contract (stx-transfer? seller-amount tx-sender tx-sender)))
      
      ;; Pay royalty to artist
      (if (not (is-eq artist tx-sender))
        (try! (as-contract (stx-transfer? royalty-fee tx-sender artist)))
        true
      )
      
      ;; Keep marketplace fee
      (var-set contract-balance (+ (var-get contract-balance) marketplace-fee))
      
      ;; Transfer ownership
      (map-set tokens token-id (merge token {
        owner: buyer,
        total-sales: (+ (get total-sales token) u1),
        total-revenue: (+ (get total-revenue token) price)
      }))
      
      ;; Deactivate offer
      (map-set token-offers { token-id: token-id, offer-id: offer-id } (merge offer {
        active: false
      }))
      
      ;; Remove from marketplace if listed
      (map-delete marketplace-listings token-id)
      
      ;; Record sale
      (record-sale token-id tx-sender buyer price marketplace-fee royalty-fee)
      
      ;; Update stats
      (var-set total-sales (+ (var-get total-sales) u1))
      (var-set total-volume (+ (var-get total-volume) price))
      
      (ok true)
    )
  )
)

;; Private helper functions
(define-private (record-sale (token-id uint) (seller principal) (buyer principal) (price uint) (marketplace-fee uint) (royalty-fee uint))
  (let (
    (token (unwrap-panic (map-get? tokens token-id)))
    (sale-id (get total-sales token))
  )
    (map-set sales-history { token-id: token-id, sale-id: sale-id } {
      seller: seller,
      buyer: buyer,
      price: price,
      sale-time: (get-current-block-height),
      marketplace-fee: marketplace-fee,
      royalty-fee: royalty-fee
    })
  )
)

(define-private (update-artist-profile (artist principal))
  (let (
    (current-profile (default-to {
      name: "",
      bio: "",
      website: none,
      verified: false,
      total-artworks: u0,
      total-sales: u0,
      total-revenue: u0
    } (map-get? artist-profiles artist)))
  )
    (map-set artist-profiles artist (merge current-profile {
      total-artworks: (+ (get total-artworks current-profile) u1)
    }))
  )
)

(define-private (update-collector-stats (collector principal) (owned-change uint) (purchased uint) (sold uint) (amount uint))
  (let (
    (current-stats (default-to {
      total-owned: u0,
      total-purchased: u0,
      total-sold: u0,
      total-spent: u0,
      total-earned: u0
    } (map-get? collection-stats collector)))
  )
    (map-set collection-stats collector {
      total-owned: (+ (get total-owned current-stats) owned-change),
      total-purchased: (+ (get total-purchased current-stats) purchased),
      total-sold: (+ (get total-sold current-stats) sold),
      total-spent: (+ (get total-spent current-stats) (if (> purchased u0) amount u0)),
      total-earned: (+ (get total-earned current-stats) (if (> sold u0) amount u0))
    })
  )
)

(define-private (get-next-offer-id (token-id uint))
  ;; Simple implementation - in production, would need better offer ID management
  u1
)

;; Read-only functions
(define-read-only (get-token-info (token-id uint))
  (map-get? tokens token-id)
)

(define-read-only (get-token-uri (token-id uint))
  (match (map-get? tokens token-id)
    token (ok (some (get image-uri token)))
    (ok none)
  )
)

(define-read-only (get-owner (token-id uint))
  (match (map-get? tokens token-id)
    token (ok (some (get owner token)))
    (ok none)
  )
)

(define-read-only (get-last-token-id)
  (ok (- (var-get next-token-id) u1))
)

(define-read-only (get-marketplace-listing (token-id uint))
  (map-get? marketplace-listings token-id)
)

(define-read-only (get-sale-history (token-id uint) (sale-id uint))
  (map-get? sales-history { token-id: token-id, sale-id: sale-id })
)

(define-read-only (get-artist-profile (artist principal))
  (map-get? artist-profiles artist)
)

(define-read-only (get-collector-stats (collector principal))
  (map-get? collection-stats collector)
)

(define-read-only (get-token-offer (token-id uint) (offer-id uint))
  (map-get? token-offers { token-id: token-id, offer-id: offer-id })
)

(define-read-only (get-marketplace-stats)
  {
    total-minted: (var-get total-minted),
    total-sales: (var-get total-sales),
    total-volume: (var-get total-volume),
    contract-balance: (var-get contract-balance)
  }
)


