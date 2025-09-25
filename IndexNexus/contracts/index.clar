;; IndexNexus Smart Contract
;; Theme: Decentralized data indexing and query optimization
;; Where Data Meets Discovery

;; Define constants
(define-constant ERR-NOT-DATA-CURATOR (err u100))
(define-constant ERR-INDEX-PROCESSED (err u101))
(define-constant ERR-INSUFFICIENT-TOKENS (err u102))
(define-constant ERR-INDEX-INACTIVE (err u103))
(define-constant ERR-PROCESSING-INCOMPLETE (err u104))
(define-constant ERR-NOT-AUTHORIZED (err u105))
(define-constant ERR-INVALID-QUERY (err u106))
(define-constant ERR-QUERY-NOT-FOUND (err u107))

;; Contract owner
(define-constant CONTRACT-OWNER tx-sender)

;; Define data maps
(define-map indexnexus-queries 
  { query-id: uint }
  {
    data-curator: principal,
    index-processor: (optional principal),
    processing-cost: uint,
    efficiency-bonus: uint,
    indexing-duration: uint,
    processing-start: (optional uint),
    query-status: (string-ascii 20)
  }
)

(define-map indexnexus-tokens principal uint)

;; New map for processor ratings
(define-map processor-ratings 
  principal 
  {
    total-jobs: uint,
    successful-jobs: uint,
    average-rating: uint
  }
)

;; New map for query categories
(define-map query-categories
  { category: (string-ascii 50) }
  {
    total-queries: uint,
    active-queries: uint
  }
)

;; Initialize IndexNexus query counter
(define-data-var indexnexus-query-counter uint u0)

;; Define functions
(define-public (submit-indexing-request (processing-cost uint) (efficiency-bonus uint) (indexing-duration uint))
  (let ((query-id (+ (var-get indexnexus-query-counter) u1)))
    (map-set indexnexus-queries 
      { query-id: query-id }
      {
        data-curator: tx-sender,
        index-processor: none,
        processing-cost: processing-cost,
        efficiency-bonus: efficiency-bonus,
        indexing-duration: indexing-duration,
        processing-start: none,
        query-status: "PENDING_PROCESSOR"
      }
    )
    (var-set indexnexus-query-counter query-id)
    (ok query-id)
  )
)

(define-public (process-data-index (query-id uint))
  (let (
    (query (unwrap! (map-get? indexnexus-queries { query-id: query-id }) ERR-INDEX-INACTIVE))
    (processor-tokens (default-to u0 (map-get? indexnexus-tokens tx-sender)))
  )
    (asserts! (is-none (get index-processor query)) ERR-INDEX-PROCESSED)
    (asserts! (>= processor-tokens (get processing-cost query)) ERR-INSUFFICIENT-TOKENS)
    
    (map-set indexnexus-queries { query-id: query-id }
      (merge query { 
        index-processor: (some tx-sender),
        processing-start: (some block-height),
        query-status: "PROCESSING"
      })
    )
    (map-set indexnexus-tokens tx-sender (- processor-tokens (get processing-cost query)))
    (map-set indexnexus-tokens (get data-curator query) (+ (default-to u0 (map-get? indexnexus-tokens (get data-curator query))) (get processing-cost query)))
    (ok true)
  )
)

(define-public (complete-indexing (query-id uint))
  (let (
    (query (unwrap! (map-get? indexnexus-queries { query-id: query-id }) ERR-INDEX-INACTIVE))
    (curator-tokens (default-to u0 (map-get? indexnexus-tokens tx-sender)))
    (total-reward (+ (get processing-cost query) (/ (* (get processing-cost query) (get efficiency-bonus query)) u100)))
  )
    (asserts! (is-eq (get data-curator query) tx-sender) ERR-NOT-DATA-CURATOR)
    (asserts! (is-eq (get query-status query) "PROCESSING") ERR-INDEX-INACTIVE)
    (asserts! (>= (- block-height (unwrap! (get processing-start query) ERR-INDEX-INACTIVE)) (get indexing-duration query)) ERR-PROCESSING-INCOMPLETE)
    (asserts! (>= curator-tokens total-reward) ERR-INSUFFICIENT-TOKENS)
    
    (map-set indexnexus-tokens tx-sender (- curator-tokens total-reward))
    (map-set indexnexus-tokens (unwrap! (get index-processor query) ERR-INDEX-INACTIVE) (+ (default-to u0 (map-get? indexnexus-tokens (unwrap! (get index-processor query) ERR-INDEX-INACTIVE))) total-reward))
    (map-set indexnexus-queries { query-id: query-id } (merge query { query-status: "INDEXED" }))
    (ok true)
  )
)

;; NEW FUNCTION 1: Cancel indexing request (allows data curator to cancel pending requests)
(define-public (cancel-indexing-request (query-id uint))
  (let (
    (query (unwrap! (map-get? indexnexus-queries { query-id: query-id }) ERR-QUERY-NOT-FOUND))
  )
    (asserts! (is-eq (get data-curator query) tx-sender) ERR-NOT-DATA-CURATOR)
    (asserts! (is-eq (get query-status query) "PENDING_PROCESSOR") ERR-INDEX-PROCESSED)
    
    (map-set indexnexus-queries { query-id: query-id }
      (merge query { query-status: "CANCELLED" })
    )
    (ok true)
  )
)

;; NEW FUNCTION 2: Rate processor (allows data curators to rate processors after completion)
(define-public (rate-processor (query-id uint) (rating uint))
  (let (
    (query (unwrap! (map-get? indexnexus-queries { query-id: query-id }) ERR-QUERY-NOT-FOUND))
    (processor (unwrap! (get index-processor query) ERR-INDEX-INACTIVE))
    (current-rating (default-to { total-jobs: u0, successful-jobs: u0, average-rating: u0 } 
                                (map-get? processor-ratings processor)))
  )
    (asserts! (is-eq (get data-curator query) tx-sender) ERR-NOT-DATA-CURATOR)
    (asserts! (is-eq (get query-status query) "INDEXED") ERR-INDEX-INACTIVE)
    (asserts! (<= rating u100) ERR-INVALID-QUERY)
    (asserts! (>= rating u1) ERR-INVALID-QUERY)
    
    (let (
      (new-total-jobs (+ (get total-jobs current-rating) u1))
      (new-successful-jobs (+ (get successful-jobs current-rating) u1))
      (new-average-rating (/ (+ (* (get average-rating current-rating) (get total-jobs current-rating)) rating) new-total-jobs))
    )
      (map-set processor-ratings processor {
        total-jobs: new-total-jobs,
        successful-jobs: new-successful-jobs,
        average-rating: new-average-rating
      })
      (ok true)
    )
  )
)

;; NEW FUNCTION 3: Bulk mint tokens (admin function for token distribution)
(define-public (mint-tokens (recipients (list 10 { recipient: principal, amount: uint })))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (fold mint-token-helper recipients (ok true))
  )
)

;; Helper function for bulk minting
(define-private (mint-token-helper (recipient-data { recipient: principal, amount: uint }) (prev-result (response bool uint)))
  (match prev-result
    success (let (
      (current-balance (default-to u0 (map-get? indexnexus-tokens (get recipient recipient-data))))
    )
      (map-set indexnexus-tokens 
        (get recipient recipient-data) 
        (+ current-balance (get amount recipient-data))
      )
      (ok true)
    )
    error prev-result
  )
)

;; Read-only functions
(define-read-only (get-query-info (query-id uint))
  (map-get? indexnexus-queries { query-id: query-id })
)

(define-read-only (get-token-balance (participant principal))
  (default-to u0 (map-get? indexnexus-tokens participant))
)

(define-read-only (get-indexnexus-stats)
  {
    total-queries: (var-get indexnexus-query-counter),
    contract-name: "IndexNexus - Where Data Meets Discovery"
  }
)

;; NEW READ-ONLY FUNCTION: Get processor rating
(define-read-only (get-processor-rating (processor principal))
  (default-to { total-jobs: u0, successful-jobs: u0, average-rating: u0 } 
              (map-get? processor-ratings processor))
)

;; NEW READ-ONLY FUNCTION: Check if query exists and get its status
(define-read-only (get-query-status (query-id uint))
  (match (map-get? indexnexus-queries { query-id: query-id })
    query (some (get query-status query))
    none
  )
)