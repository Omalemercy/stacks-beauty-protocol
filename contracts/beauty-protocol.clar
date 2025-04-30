;; beauty-protocol.clar
;; A contract that manages the Stacks Beauty Protocol ecosystem, including content registration,
;; reputation tracking, user profiles, recommendation mechanisms, and token rewards.
;; The protocol connects beauty content creators with users seeking personalized
;; recommendations while establishing incentives for quality content through tokenization.

;; ========== Error Constants ==========
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ALREADY-REGISTERED (err u101))
(define-constant ERR-USER-NOT-FOUND (err u102))
(define-constant ERR-CREATOR-NOT-FOUND (err u103))
(define-constant ERR-CONTENT-NOT-FOUND (err u104))
(define-constant ERR-INVALID-RATING (err u105))
(define-constant ERR-ALREADY-RATED (err u106))
(define-constant ERR-INVALID-SKIN-TYPE (err u107))
(define-constant ERR-INVALID-CONCERN (err u108))
(define-constant ERR-INVALID-GOAL (err u109))
(define-constant ERR-INSUFFICIENT-REWARDS (err u110))

;; ========== Constants ==========
(define-constant CREATOR-REGISTRATION-FEE u100) ;; in microSTX
(define-constant MIN-RATING u1)
(define-constant MAX-RATING u5)
(define-constant BASE-CONTENT-REWARD u10) ;; Base reward for content interactions
(define-constant REPUTATION-MULTIPLIER u2) ;; Multiplier for high reputation creators

;; Valid skin types, concerns, and goals for validation
(define-constant VALID-SKIN-TYPES (list "dry" "oily" "combination" "normal" "sensitive"))
(define-constant VALID-CONCERNS (list "acne" "aging" "pigmentation" "redness" "dryness" "sensitivity"))
(define-constant VALID-GOALS (list "hydration" "anti-aging" "clearer-skin" "brightening" "sun-protection"))

;; ========== Data Maps and Variables ==========
;; Tracks user profiles with their skin types, concerns, and goals
(define-map user-profiles
  { user: principal }
  {
    skin-type: (string-ascii 20),
    concerns: (list 5 (string-ascii 20)),
    goals: (list 3 (string-ascii 20)),
    joined-at: uint,
    rewards-balance: uint
  }
)

;; Tracks content creator information
(define-map creators
  { creator: principal }
  {
    reputation-score: uint,
    content-count: uint,
    total-ratings: uint,
    registered-at: uint,
    rewards-balance: uint
  }
)

;; Stores beauty content (tutorials, recommendations, routines)
(define-map beauty-content
  { content-id: uint }
  {
    creator: principal,
    title: (string-ascii 100),
    content-type: (string-ascii 20), ;; "tutorial", "recommendation", "routine"
    skin-types: (list 5 (string-ascii 20)),
    concerns: (list 5 (string-ascii 20)),
    goals: (list 3 (string-ascii 20)),
    created-at: uint,
    rating-sum: uint,
    rating-count: uint
  }
)

;; Tracks which users have rated which content
(define-map user-ratings
  { user: principal, content-id: uint }
  { rating: uint, timestamp: uint }
)

;; Tracks user beauty journey results
(define-map beauty-journeys
  { user: principal, journey-id: uint }
  {
    content-id: uint, ;; The recommended content being followed
    start-date: uint,
    end-date: uint,
    result-rating: uint,
    verified: bool
  }
)

;; Counter for content IDs
(define-data-var next-content-id uint u1)

;; Counter for journey IDs
(define-data-var next-journey-id uint u1)

;; ========== Private Functions ==========
;; Validates that the provided skin type is valid
(define-private (is-valid-skin-type (skin-type (string-ascii 20)))
  (default-to false (some (lambda (valid-type) (is-eq valid-type skin-type)) VALID-SKIN-TYPES))
)

;; Validates that all provided skin types are valid
(define-private (validate-skin-types (skin-types (list 5 (string-ascii 20))))
  (fold and true (map is-valid-skin-type skin-types))
)

;; Validates that the provided concern is valid
(define-private (is-valid-concern (concern (string-ascii 20)))
  (default-to false (some (lambda (valid-concern) (is-eq valid-concern concern)) VALID-CONCERNS))
)

;; Validates that all provided concerns are valid
(define-private (validate-concerns (concerns (list 5 (string-ascii 20))))
  (fold and true (map is-valid-concern concerns))
)

;; Validates that the provided goal is valid
(define-private (is-valid-goal (goal (string-ascii 20)))
  (default-to false (some (lambda (valid-goal) (is-eq valid-goal goal)) VALID-GOALS))
)

;; Validates that all provided goals are valid
(define-private (validate-goals (goals (list 3 (string-ascii 20))))
  (fold and true (map is-valid-goal goals))
)

;; Calculates reward amount based on rating and creator's reputation
(define-private (calculate-reward (rating uint) (creator principal))
  (let (
    (creator-data (unwrap-panic (map-get? creators { creator: creator })))
    (base-reward (* rating BASE-CONTENT-REWARD))
    (reputation-factor (/ (get reputation-score creator-data) u100))
  )
  (if (> reputation-factor u0)
    (+ base-reward (* base-reward reputation-factor REPUTATION-MULTIPLIER))
    base-reward
  ))
)

;; Updates a creator's reputation based on new rating
(define-private (update-reputation (creator principal) (rating uint))
  (let (
    (creator-data (unwrap-panic (map-get? creators { creator: creator })))
    (current-reputation (get reputation-score creator-data))
    (content-count (get content-count creator-data))
    (total-ratings (get total-ratings creator-data))
    ;; Simple weighted average for reputation
    (new-total-ratings (+ total-ratings u1))
    (new-reputation (/ (+ (* current-reputation total-ratings) (* rating u20)) new-total-ratings))
  )
  (map-set creators 
    { creator: creator }
    (merge creator-data {
      reputation-score: new-reputation,
      total-ratings: new-total-ratings
    })
  ))
)

;; ========== Read-Only Functions ==========
;; Returns user profile information
(define-read-only (get-user-profile (user principal))
  (map-get? user-profiles { user: user })
)

;; Returns creator information
(define-read-only (get-creator-info (creator principal))
  (map-get? creators { creator: creator })
)

;; Returns content details
(define-read-only (get-content (content-id uint))
  (map-get? beauty-content { content-id: content-id })
)

;; Returns the user's rating for specific content
(define-read-only (get-user-content-rating (user principal) (content-id uint))
  (map-get? user-ratings { user: user, content-id: content-id })
)

;; Returns a user's beauty journey record
(define-read-only (get-beauty-journey (user principal) (journey-id uint))
  (map-get? beauty-journeys { user: user, journey-id: journey-id })
)

;; Returns the average rating for a piece of content
(define-read-only (get-content-average-rating (content-id uint))
  (match (map-get? beauty-content { content-id: content-id })
    content (let (
      (rating-sum (get rating-sum content))
      (rating-count (get rating-count content))
    )
    (if (> rating-count u0)
      (ok (/ rating-sum rating-count))
      (ok u0)
    ))
    (err ERR-CONTENT-NOT-FOUND)
  )
)

;; Finds personalized recommendations for a user based on their profile
(define-read-only (get-recommendations (user principal) (limit uint))
  (match (map-get? user-profiles { user: user })
    profile 
    (let (
      (user-skin-type (get skin-type profile))
      (user-concerns (get concerns profile))
      (user-goals (get goals profile))
      ;; This is a simplified recommendation logic - in a real implementation,
      ;; you would need off-chain indexing to handle complex queries
      ;; Here we just return basic information for further processing
    )
    (ok {
      skin-type: user-skin-type,
      concerns: user-concerns,
      goals: user-goals,
      recommended-content-ids: (list) ;; placeholder - would need off-chain indexing
    }))
    (err ERR-USER-NOT-FOUND)
  )
)

;; ========== Public Functions ==========
;; Register a new user profile
(define-public (register-user-profile 
  (skin-type (string-ascii 20))
  (concerns (list 5 (string-ascii 20)))
  (goals (list 3 (string-ascii 20)))
)
  (let (
    (user tx-sender)
  )
    ;; Validate inputs
    (asserts! (is-valid-skin-type skin-type) (err ERR-INVALID-SKIN-TYPE))
    (asserts! (validate-concerns concerns) (err ERR-INVALID-CONCERN))
    (asserts! (validate-goals goals) (err ERR-INVALID-GOAL))
    
    ;; Check if user is already registered
    (asserts! (is-none (map-get? user-profiles { user: user })) (err ERR-ALREADY-REGISTERED))
    
    ;; Register the user profile
    (map-set user-profiles
      { user: user }
      {
        skin-type: skin-type,
        concerns: concerns,
        goals: goals,
        joined-at: block-height,
        rewards-balance: u0
      }
    )
    (ok true)
  )
)

;; Update an existing user profile
(define-public (update-user-profile 
  (skin-type (string-ascii 20))
  (concerns (list 5 (string-ascii 20)))
  (goals (list 3 (string-ascii 20)))
)
  (let (
    (user tx-sender)
    (existing-profile (map-get? user-profiles { user: user }))
  )
    ;; Validate inputs
    (asserts! (is-valid-skin-type skin-type) (err ERR-INVALID-SKIN-TYPE))
    (asserts! (validate-concerns concerns) (err ERR-INVALID-CONCERN))
    (asserts! (validate-goals goals) (err ERR-INVALID-GOAL))
    
    ;; Check if user exists
    (asserts! (is-some existing-profile) (err ERR-USER-NOT-FOUND))
    
    ;; Update the user profile while preserving other fields
    (map-set user-profiles
      { user: user }
      (merge (unwrap-panic existing-profile) {
        skin-type: skin-type,
        concerns: concerns,
        goals: goals
      })
    )
    (ok true)
  )
)

;; Register as a content creator
(define-public (register-as-creator)
  (let (
    (creator tx-sender)
  )
    ;; Check if already registered
    (asserts! (is-none (map-get? creators { creator: creator })) (err ERR-ALREADY-REGISTERED))
    
    ;; Collect registration fee
    (try! (stx-transfer? CREATOR-REGISTRATION-FEE tx-sender (as-contract tx-sender)))
    
    ;; Register the creator
    (map-set creators
      { creator: creator }
      {
        reputation-score: u100, ;; Starting reputation of 100
        content-count: u0,
        total-ratings: u0,
        registered-at: block-height,
        rewards-balance: u0
      }
    )
    (ok true)
  )
)

;; Publish new beauty content
(define-public (publish-content
  (title (string-ascii 100))
  (content-type (string-ascii 20))
  (skin-types (list 5 (string-ascii 20)))
  (concerns (list 5 (string-ascii 20)))
  (goals (list 3 (string-ascii 20)))
)
  (let (
    (creator tx-sender)
    (content-id (var-get next-content-id))
    (creator-data (map-get? creators { creator: creator }))
  )
    ;; Ensure creator is registered
    (asserts! (is-some creator-data) (err ERR-CREATOR-NOT-FOUND))
    
    ;; Validate inputs
    (asserts! (validate-skin-types skin-types) (err ERR-INVALID-SKIN-TYPE))
    (asserts! (validate-concerns concerns) (err ERR-INVALID-CONCERN))
    (asserts! (validate-goals goals) (err ERR-INVALID-GOAL))
    
    ;; Store content information
    (map-set beauty-content
      { content-id: content-id }
      {
        creator: creator,
        title: title,
        content-type: content-type,
        skin-types: skin-types,
        concerns: concerns,
        goals: goals,
        created-at: block-height,
        rating-sum: u0,
        rating-count: u0
      }
    )
    
    ;; Update creator's content count
    (map-set creators
      { creator: creator }
      (merge (unwrap-panic creator-data) {
        content-count: (+ (get content-count (unwrap-panic creator-data)) u1)
      })
    )
    
    ;; Increment content ID counter
    (var-set next-content-id (+ content-id u1))
    
    (ok content-id)
  )
)

;; Rate content and reward creator
(define-public (rate-content (content-id uint) (rating uint))
  (let (
    (user tx-sender)
    (content (map-get? beauty-content { content-id: content-id }))
  )
    ;; Validate inputs and state
    (asserts! (and (>= rating MIN-RATING) (<= rating MAX-RATING)) (err ERR-INVALID-RATING))
    (asserts! (is-some content) (err ERR-CONTENT-NOT-FOUND))
    (asserts! (is-none (map-get? user-ratings { user: user, content-id: content-id })) (err ERR-ALREADY-RATED))
    
    (let (
      (content-data (unwrap-panic content))
      (creator (get creator content-data))
      (new-rating-sum (+ (get rating-sum content-data) rating))
      (new-rating-count (+ (get rating-count content-data) u1))
      (reward-amount (calculate-reward rating creator))
    )
      ;; Record the user's rating
      (map-set user-ratings
        { user: user, content-id: content-id }
        { rating: rating, timestamp: block-height }
      )
      
      ;; Update content ratings
      (map-set beauty-content
        { content-id: content-id }
        (merge content-data {
          rating-sum: new-rating-sum,
          rating-count: new-rating-count
        })
      )
      
      ;; Update creator's reputation
      (update-reputation creator rating)
      
      ;; Add rewards to creator's balance
      (let (
        (creator-data (unwrap-panic (map-get? creators { creator: creator })))
      )
        (map-set creators
          { creator: creator }
          (merge creator-data {
            rewards-balance: (+ (get rewards-balance creator-data) reward-amount)
          })
        )
      )
      
      (ok rating)
    )
  )
)

;; Start a new beauty journey (tracking use of a recommendation)
(define-public (start-beauty-journey (content-id uint))
  (let (
    (user tx-sender)
    (journey-id (var-get next-journey-id))
    (content (map-get? beauty-content { content-id: content-id }))
    (user-profile (map-get? user-profiles { user: user }))
  )
    ;; Validate inputs
    (asserts! (is-some content) (err ERR-CONTENT-NOT-FOUND))
    (asserts! (is-some user-profile) (err ERR-USER-NOT-FOUND))
    
    ;; Record the journey
    (map-set beauty-journeys
      { user: user, journey-id: journey-id }
      {
        content-id: content-id,
        start-date: block-height,
        end-date: u0, ;; Will be set when journey ends
        result-rating: u0, ;; Will be set when journey ends
        verified: false
      }
    )
    
    ;; Increment journey ID counter
    (var-set next-journey-id (+ journey-id u1))
    
    (ok journey-id)
  )
)

;; Complete a beauty journey with results
(define-public (complete-beauty-journey (journey-id uint) (result-rating uint))
  (let (
    (user tx-sender)
    (journey (map-get? beauty-journeys { user: user, journey-id: journey-id }))
  )
    ;; Validate inputs
    (asserts! (is-some journey) (err ERR-USER-NOT-FOUND))
    (asserts! (and (>= result-rating MIN-RATING) (<= result-rating MAX-RATING)) (err ERR-INVALID-RATING))
    
    (let (
      (journey-data (unwrap-panic journey))
      (content-id (get content-id journey-data))
      (content (unwrap-panic (map-get? beauty-content { content-id: content-id })))
      (creator (get creator content))
      (reward-amount (* result-rating BASE-CONTENT-REWARD REPUTATION-MULTIPLIER))
    )
      ;; Update journey record
      (map-set beauty-journeys
        { user: user, journey-id: journey-id }
        (merge journey-data {
          end-date: block-height,
          result-rating: result-rating,
          verified: true
        })
      )
      
      ;; Add additional rewards to creator for successful outcomes
      (let (
        (creator-data (unwrap-panic (map-get? creators { creator: creator })))
      )
        (map-set creators
          { creator: creator }
          (merge creator-data {
            rewards-balance: (+ (get rewards-balance creator-data) reward-amount)
          })
        )
      )
      
      ;; Add rewards to user for completing journey
      (let (
        (user-data (unwrap-panic (map-get? user-profiles { user: user })))
      )
        (map-set user-profiles
          { user: user }
          (merge user-data {
            rewards-balance: (+ (get rewards-balance user-data) (/ reward-amount u2))
          })
        )
      )
      
      (ok true)
    )
  )
)

;; Allow creator to withdraw accumulated rewards
(define-public (withdraw-creator-rewards)
  (let (
    (creator tx-sender)
    (creator-data (map-get? creators { creator: creator }))
  )
    ;; Validate
    (asserts! (is-some creator-data) (err ERR-CREATOR-NOT-FOUND))
    
    (let (
      (rewards (get rewards-balance (unwrap-panic creator-data)))
    )
      ;; Ensure there are rewards to withdraw
      (asserts! (> rewards u0) (err ERR-INSUFFICIENT-REWARDS))
      
      ;; Reset rewards balance
      (map-set creators
        { creator: creator }
        (merge (unwrap-panic creator-data) {
          rewards-balance: u0
        })
      )
      
      ;; Transfer rewards (in a real implementation, this would transfer tokens)
      ;; Here we're just simulating the reward withdrawal
      (ok rewards)
    )
  )
)

;; Allow user to withdraw accumulated rewards
(define-public (withdraw-user-rewards)
  (let (
    (user tx-sender)
    (user-data (map-get? user-profiles { user: user }))
  )
    ;; Validate
    (asserts! (is-some user-data) (err ERR-USER-NOT-FOUND))
    
    (let (
      (rewards (get rewards-balance (unwrap-panic user-data)))
    )
      ;; Ensure there are rewards to withdraw
      (asserts! (> rewards u0) (err ERR-INSUFFICIENT-REWARDS))
      
      ;; Reset rewards balance
      (map-set user-profiles
        { user: user }
        (merge (unwrap-panic user-data) {
          rewards-balance: u0
        })
      )
      
      ;; Transfer rewards (in a real implementation, this would transfer tokens)
      ;; Here we're just simulating the reward withdrawal
      (ok rewards)
    )
  )
)