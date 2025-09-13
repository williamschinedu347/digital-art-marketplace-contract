;; Digital Art Curation Smart Contract
;; Professional curation system for quality control and art collection management

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u400))
(define-constant ERR-NOT-CURATOR (err u401))
(define-constant ERR-ARTWORK-NOT-FOUND (err u402))
(define-constant ERR-ALREADY-CURATED (err u403))
(define-constant ERR-INVALID-SCORE (err u404))
(define-constant ERR-COLLECTION-NOT-FOUND (err u405))
(define-constant ERR-INVALID-EXHIBITION (err u406))
(define-constant ERR-ARTIST-NOT-VERIFIED (err u407))
(define-constant ERR-INSUFFICIENT-VOTES (err u408))
(define-constant ERR-ALREADY-VOTED (err u409))
(define-constant ERR-EXHIBITION-ENDED (err u410))

;; Contract constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant MIN-CURATION-SCORE u1)
(define-constant MAX-CURATION-SCORE u10)
(define-constant CURATOR-THRESHOLD u100) ;; Minimum reputation to become curator
(define-constant MIN-VOTES-REQUIRED u5)
(define-constant EXHIBITION-DURATION u4320) ;; ~30 days in blocks
(define-constant VERIFICATION-DEPOSIT u1000000) ;; 1M microSTX

;; Curation status constants
(define-constant STATUS-PENDING u0)
(define-constant STATUS-APPROVED u1)
(define-constant STATUS-REJECTED u2)
(define-constant STATUS-FEATURED u3)
(define-constant STATUS-DISPUTED u4)

;; Quality tier constants
(define-constant TIER-BRONZE u1)
(define-constant TIER-SILVER u2)
(define-constant TIER-GOLD u3)
(define-constant TIER-PLATINUM u4)

;; Data variables
(define-data-var next-curation-id uint u1)
(define-data-var next-collection-id uint u1)
(define-data-var next-exhibition-id uint u1)
(define-data-var total-curators uint u0)
(define-data-var total-verified-artists uint u0)

;; Data maps
(define-map curation-submissions
  uint
  {
    submitter: principal,
    artwork-id: uint,
    artwork-contract: principal,
    submission-time: uint,
    status: uint,
    curator: (optional principal),
    quality-score: (optional uint),
    tier: (optional uint),
    review-notes: (optional (string-ascii 500)),
    community-votes: uint,
    community-score: uint
  }
)

(define-map curators
  principal
  {
    name: (string-ascii 100),
    bio: (string-ascii 500),
    specialization: (string-ascii 100),
    reputation-score: uint,
    total-curations: uint,
    successful-curations: uint,
    verification-time: uint,
    active: bool
  }
)

(define-map artist-verifications
  principal
  {
    artist-name: (string-ascii 100),
    real-name: (optional (string-ascii 100)),
    bio: (string-ascii 500),
    portfolio-links: (list 3 (string-ascii 200)),
    verification-documents: (buff 32),
    verifier: principal,
    verification-time: uint,
    status: uint,
    deposit-amount: uint
  }
)

(define-map curated-collections
  uint
  {
    creator: principal,
    title: (string-ascii 100),
    description: (string-ascii 500),
    theme: (string-ascii 100),
    creation-time: uint,
    artwork-count: uint,
    total-value: uint,
    featured: bool,
    visibility: bool
  }
)

(define-map collection-artworks
  { collection-id: uint, artwork-index: uint }
  {
    curation-id: uint,
    added-time: uint,
    position: uint
  }
)

(define-map exhibitions
  uint
  {
    host: principal,
    title: (string-ascii 100),
    description: (string-ascii 500),
    start-time: uint,
    end-time: uint,
    venue-type: (string-ascii 50), ;; "virtual", "physical", "hybrid"
    featured-collection: (optional uint),
    visitor-count: uint,
    status: uint
  }
)

(define-map community-votes
  { curation-id: uint, voter: principal }
  {
    score: uint,
    vote-time: uint,
    comment: (optional (string-ascii 200))
  }
)

(define-map curator-applications
  principal
  {
    applicant-name: (string-ascii 100),
    experience: (string-ascii 500),
    portfolio: (string-ascii 200),
    references: (list 3 (string-ascii 200)),
    application-time: uint,
    status: uint,
    reviewer: (optional principal)
  }
)

;; Authorization functions
(define-private (is-contract-owner)
  (is-eq tx-sender CONTRACT-OWNER)
)

(define-private (is-curator (user principal))
  (match (map-get? curators user)
    curator (get active curator)
    false
  )
)

(define-private (is-verified-artist (artist principal))
  (match (map-get? artist-verifications artist)
    verification (is-eq (get status verification) STATUS-APPROVED)
    false
  )
)

;; Utility functions
(define-private (is-valid-score (score uint))
  (and (>= score MIN-CURATION-SCORE)
       (<= score MAX-CURATION-SCORE))
)

(define-private (calculate-tier (score uint))
  (if (<= score u4)
    TIER-BRONZE
    (if (<= score u6)
      TIER-SILVER
      (if (<= score u8)
        TIER-GOLD
        TIER-PLATINUM
      )
    )
  )
)

(define-private (get-current-block-height)
  block-height
)

;; Core curation submission function
(define-public (submit-for-curation (artwork-id uint) (artwork-contract principal))
  (let (
    (curation-id (var-get next-curation-id))
    (current-height (get-current-block-height))
  )
    ;; Create curation submission
    (map-set curation-submissions curation-id {
      submitter: tx-sender,
      artwork-id: artwork-id,
      artwork-contract: artwork-contract,
      submission-time: current-height,
      status: STATUS-PENDING,
      curator: none,
      quality-score: none,
      tier: none,
      review-notes: none,
      community-votes: u0,
      community-score: u0
    })
    
    ;; Update counter
    (var-set next-curation-id (+ curation-id u1))
    
    (ok curation-id)
  )
)

;; Professional curation by authorized curators
(define-public (curate-artwork (curation-id uint) 
                              (quality-score uint) 
                              (approve bool)
                              (review-notes (string-ascii 500)))
  (let (
    (submission (unwrap! (map-get? curation-submissions curation-id) ERR-ARTWORK-NOT-FOUND))
    (current-height (get-current-block-height))
    (tier (calculate-tier quality-score))
  )
    (asserts! (is-curator tx-sender) ERR-NOT-CURATOR)
    (asserts! (is-eq (get status submission) STATUS-PENDING) ERR-ALREADY-CURATED)
    (asserts! (is-valid-score quality-score) ERR-INVALID-SCORE)
    
    ;; Update curation submission
    (map-set curation-submissions curation-id (merge submission {
      status: (if approve STATUS-APPROVED STATUS-REJECTED),
      curator: (some tx-sender),
      quality-score: (some quality-score),
      tier: (some tier),
      review-notes: (some review-notes)
    }))
    
    ;; Update curator statistics
    (update-curator-stats tx-sender approve)
    
    (ok approve)
  )
)

;; Community voting on artwork quality
(define-public (vote-on-quality (curation-id uint) (score uint) (comment (optional (string-ascii 200))))
  (let (
    (submission (unwrap! (map-get? curation-submissions curation-id) ERR-ARTWORK-NOT-FOUND))
    (current-height (get-current-block-height))
  )
    (asserts! (is-valid-score score) ERR-INVALID-SCORE)
    (asserts! (is-none (map-get? community-votes { curation-id: curation-id, voter: tx-sender })) ERR-ALREADY-VOTED)
    (asserts! (not (is-eq tx-sender (get submitter submission))) ERR-NOT-AUTHORIZED)
    
    ;; Record vote
    (map-set community-votes { curation-id: curation-id, voter: tx-sender } {
      score: score,
      vote-time: current-height,
      comment: comment
    })
    
    ;; Update submission with new vote data
    (let (
      (current-votes (get community-votes submission))
      (current-total-score (get community-score submission))
      (new-vote-count (+ current-votes u1))
      (new-total-score (+ current-total-score score))
    )
      (map-set curation-submissions curation-id (merge submission {
        community-votes: new-vote-count,
        community-score: new-total-score
      }))
    )
    
    (ok true)
  )
)

;; Create curated collection
(define-public (create-collection (title (string-ascii 100))
                                 (description (string-ascii 500))
                                 (theme (string-ascii 100))
                                 (curation-ids (list 10 uint)))
  (let (
    (collection-id (var-get next-collection-id))
    (current-height (get-current-block-height))
  )
    (asserts! (is-curator tx-sender) ERR-NOT-CURATOR)
    (asserts! (> (len title) u0) ERR-INVALID-EXHIBITION)
    
    ;; Create collection
    (map-set curated-collections collection-id {
      creator: tx-sender,
      title: title,
      description: description,
      theme: theme,
      creation-time: current-height,
      artwork-count: (len curation-ids),
      total-value: u0, ;; Would need artwork value calculation
      featured: false,
      visibility: true
    })
    
    ;; Add artworks to collection
    (add-artworks-to-collection collection-id curation-ids)
    
    ;; Update counter
    (var-set next-collection-id (+ collection-id u1))
    
    (ok collection-id)
  )
)

;; Artist verification process
(define-public (verify-artist (artist-name (string-ascii 100))
                             (real-name (optional (string-ascii 100)))
                             (bio (string-ascii 500))
                             (portfolio-links (list 3 (string-ascii 200)))
                             (verification-documents (buff 32)))
  (let (
    (current-height (get-current-block-height))
  )
    ;; Require verification deposit
    (try! (stx-transfer? VERIFICATION-DEPOSIT tx-sender (as-contract tx-sender)))
    
    ;; Create verification record
    (map-set artist-verifications tx-sender {
      artist-name: artist-name,
      real-name: real-name,
      bio: bio,
      portfolio-links: portfolio-links,
      verification-documents: verification-documents,
      verifier: tx-sender, ;; Will be updated by verifier
      verification-time: current-height,
      status: STATUS-PENDING,
      deposit-amount: VERIFICATION-DEPOSIT
    })
    
    (ok true)
  )
)

;; Approve artist verification (curator only)
(define-public (approve-artist-verification (artist principal) (approve bool))
  (let (
    (verification (unwrap! (map-get? artist-verifications artist) ERR-ARTIST-NOT-VERIFIED))
    (current-height (get-current-block-height))
  )
    (asserts! (is-curator tx-sender) ERR-NOT-CURATOR)
    (asserts! (is-eq (get status verification) STATUS-PENDING) ERR-ALREADY-CURATED)
    
    ;; Update verification status
    (map-set artist-verifications artist (merge verification {
      status: (if approve STATUS-APPROVED STATUS-REJECTED),
      verifier: tx-sender,
      verification-time: current-height
    }))
    
    ;; Return deposit if approved
    (if approve
      (begin
        (try! (as-contract (stx-transfer? (get deposit-amount verification) tx-sender artist)))
        (var-set total-verified-artists (+ (var-get total-verified-artists) u1))
      )
      true
    )
    
    (ok approve)
  )
)

;; Host virtual exhibition
(define-public (host-exhibition (title (string-ascii 100))
                               (description (string-ascii 500))
                               (venue-type (string-ascii 50))
                               (featured-collection (optional uint))
                               (duration-blocks uint))
  (let (
    (exhibition-id (var-get next-exhibition-id))
    (current-height (get-current-block-height))
    (end-time (+ current-height (if (> duration-blocks u0) duration-blocks EXHIBITION-DURATION)))
  )
    (asserts! (is-curator tx-sender) ERR-NOT-CURATOR)
    (asserts! (> (len title) u0) ERR-INVALID-EXHIBITION)
    
    ;; Validate featured collection if provided
    (match featured-collection
      collection-id (asserts! (is-some (map-get? curated-collections collection-id)) ERR-COLLECTION-NOT-FOUND)
      true
    )
    
    ;; Create exhibition
    (map-set exhibitions exhibition-id {
      host: tx-sender,
      title: title,
      description: description,
      start-time: current-height,
      end-time: end-time,
      venue-type: venue-type,
      featured-collection: featured-collection,
      visitor-count: u0,
      status: STATUS-APPROVED
    })
    
    ;; Update counter
    (var-set next-exhibition-id (+ exhibition-id u1))
    
    (ok exhibition-id)
  )
)

;; Apply to become curator
(define-public (apply-for-curator (applicant-name (string-ascii 100))
                                 (experience (string-ascii 500))
                                 (portfolio (string-ascii 200))
                                 (references (list 3 (string-ascii 200))))
  (let (
    (current-height (get-current-block-height))
  )
    (asserts! (not (is-curator tx-sender)) ERR-NOT-AUTHORIZED)
    
    ;; Create application
    (map-set curator-applications tx-sender {
      applicant-name: applicant-name,
      experience: experience,
      portfolio: portfolio,
      references: references,
      application-time: current-height,
      status: STATUS-PENDING,
      reviewer: none
    })
    
    (ok true)
  )
)

;; Approve curator application (owner only)
(define-public (approve-curator-application (applicant principal) (approve bool))
  (let (
    (application (unwrap! (map-get? curator-applications applicant) ERR-NOT-AUTHORIZED))
    (current-height (get-current-block-height))
  )
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status application) STATUS-PENDING) ERR-ALREADY-CURATED)
    
    ;; Update application
    (map-set curator-applications applicant (merge application {
      status: (if approve STATUS-APPROVED STATUS-REJECTED),
      reviewer: (some tx-sender)
    }))
    
    ;; Create curator profile if approved
    (if approve
      (begin
        (map-set curators applicant {
          name: (get applicant-name application),
          bio: (get experience application),
          specialization: "General",
          reputation-score: CURATOR-THRESHOLD,
          total-curations: u0,
          successful-curations: u0,
          verification-time: current-height,
          active: true
        })
        (var-set total-curators (+ (var-get total-curators) u1))
      )
      true
    )
    
    (ok approve)
  )
)

;; Private helper functions
(define-private (update-curator-stats (curator principal) (success bool))
  (let (
    (current-stats (unwrap-panic (map-get? curators curator)))
  )
    (map-set curators curator (merge current-stats {
      total-curations: (+ (get total-curations current-stats) u1),
      successful-curations: (if success 
        (+ (get successful-curations current-stats) u1)
        (get successful-curations current-stats)
      ),
      reputation-score: (calculate-curator-reputation 
        (+ (get total-curations current-stats) u1)
        (if success 
          (+ (get successful-curations current-stats) u1)
          (get successful-curations current-stats)
        )
      )
    }))
  )
)

(define-private (calculate-curator-reputation (total uint) (successful uint))
  (if (> total u0)
    (+ CURATOR-THRESHOLD (/ (* successful u50) total))
    CURATOR-THRESHOLD
  )
)

(define-private (add-artworks-to-collection (collection-id uint) (curation-ids (list 10 uint)))
  (let (
    (current-height (get-current-block-height))
  )
    ;; This is a simplified implementation
    ;; In production, would iterate through the list and add each artwork
    true
  )
)

;; Visit exhibition (increment visitor count)
(define-public (visit-exhibition (exhibition-id uint))
  (let (
    (exhibition (unwrap! (map-get? exhibitions exhibition-id) ERR-EXHIBITION-ENDED))
    (current-height (get-current-block-height))
  )
    (asserts! (<= (get start-time exhibition) current-height) ERR-EXHIBITION-ENDED)
    (asserts! (>= (get end-time exhibition) current-height) ERR-EXHIBITION-ENDED)
    
    ;; Increment visitor count
    (map-set exhibitions exhibition-id (merge exhibition {
      visitor-count: (+ (get visitor-count exhibition) u1)
    }))
    
    (ok true)
  )
)

;; Read-only functions
(define-read-only (get-curation-submission (curation-id uint))
  (map-get? curation-submissions curation-id)
)

(define-read-only (get-curator-profile (curator principal))
  (map-get? curators curator)
)

(define-read-only (get-artist-verification (artist principal))
  (map-get? artist-verifications artist)
)

(define-read-only (get-collection (collection-id uint))
  (map-get? curated-collections collection-id)
)

(define-read-only (get-exhibition (exhibition-id uint))
  (map-get? exhibitions exhibition-id)
)

(define-read-only (get-community-vote (curation-id uint) (voter principal))
  (map-get? community-votes { curation-id: curation-id, voter: voter })
)

(define-read-only (get-curator-application (applicant principal))
  (map-get? curator-applications applicant)
)

(define-read-only (get-curation-stats)
  {
    total-submissions: (- (var-get next-curation-id) u1),
    total-collections: (- (var-get next-collection-id) u1),
    total-exhibitions: (- (var-get next-exhibition-id) u1),
    total-curators: (var-get total-curators),
    verified-artists: (var-get total-verified-artists)
  }
)

(define-read-only (calculate-community-average (curation-id uint))
  (match (map-get? curation-submissions curation-id)
    submission 
      (let (
        (total-votes (get community-votes submission))
        (total-score (get community-score submission))
      )
        (if (> total-votes u0)
          (some (/ total-score total-votes))
          none
        )
      )
    none
  )
)


;; title: digital-art-curation
;; version:
;; summary:
;; description:

;; traits
;;

;; token definitions
;;

;; constants
;;

;; data vars
;;

;; data maps
;;

;; public functions
;;

;; read only functions
;;

;; private functions
;;

