;; local-vault.clar
;; A decentralized utility for managing local resource access and governance
;; This contract provides flexible access control and community management tools

;; ============================================
;; Error constants
;; ============================================
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-RESOURCE-NOT-FOUND (err u101))
(define-constant ERR-ALREADY-REGISTERED (err u102))
(define-constant ERR-INVALID-ACCESS-TYPE (err u103))
(define-constant ERR-ACCESS-DENIED (err u104))
(define-constant ERR-INVALID-PARAMETERS (err u105))
(define-constant ERR-NO-ACTIVE-PROPOSAL (err u106))
(define-constant ERR-ALREADY-VOTED (err u107))

;; ============================================
;; Access types
;; ============================================
(define-constant ACCESS-TYPE-PUBLIC u1)
(define-constant ACCESS-TYPE-PRIVATE u2)
(define-constant ACCESS-TYPE-RESTRICTED u3)

;; ============================================
;; Data maps and variables
;; ============================================

;; Contract administrator
(define-data-var contract-admin principal tx-sender)

;; Member registry
(define-map members
  { member-id: principal }
  {
    name: (string-ascii 100),
    role: (string-ascii 50),
    joined-at: uint,
    contribution-count: uint
  }
)

;; Resource registry
(define-map resources
  { resource-id: (string-ascii 36) }
  {
    title: (string-ascii 100),
    description: (string-ascii 255),
    category: (string-ascii 50),
    owner: principal,
    access-type: uint,
    created-at: uint,
    verified: bool
  }
)

;; Access permissions for restricted resources
(define-map resource-permissions
  { resource-id: (string-ascii 36), user: principal }
  { 
    has-access: bool,
    granted-at: uint,
    granted-by: principal
  }
)

;; Governance proposals
(define-map governance-proposals
  { proposal-id: uint }
  {
    title: (string-ascii 100),
    description: (string-ascii 500),
    proposer: principal,
    proposed-at: uint,
    voting-ends-at: uint,
    yes-votes: uint,
    no-votes: uint,
    status: (string-ascii 20)
  }
)

;; Proposal voting tracking
(define-map proposal-votes
  { proposal-id: uint, voter: principal }
  { vote: bool }
)

;; Track the next proposal ID
(define-data-var next-proposal-id uint u1)

;; ============================================
;; Private functions
;; ============================================

;; Validates the access type
(define-private (is-valid-access-type (access-type uint))
  (or
    (is-eq access-type ACCESS-TYPE-PUBLIC)
    (is-eq access-type ACCESS-TYPE-PRIVATE)
    (is-eq access-type ACCESS-TYPE-RESTRICTED)
  )
)

;; ============================================
;; Read-only functions
;; ============================================

;; Get member information
(define-read-only (get-member (member-id principal))
  (map-get? members { member-id: member-id })
)

;; Get resource information
(define-read-only (get-resource (resource-id (string-ascii 36)))
  (map-get? resources { resource-id: resource-id })
)

;; Get access permission details
(define-read-only (get-access-permission (resource-id (string-ascii 36)) (user principal))
  (map-get? resource-permissions { resource-id: resource-id, user: user })
)

;; Get proposal details
(define-read-only (get-proposal (proposal-id uint))
  (map-get? governance-proposals { proposal-id: proposal-id })
)

;; Check if a user has voted on a proposal
(define-read-only (has-voted (proposal-id uint) (voter principal))
  (map-get? proposal-votes { proposal-id: proposal-id, voter: voter })
)

;; ============================================
;; Public functions
;; ============================================

;; Verify a resource (admin function)
(define-public (verify-resource (resource-id (string-ascii 36)))
  (let (
    (resource (map-get? resources { resource-id: resource-id }))
    (current-admin (var-get contract-admin))
  )
    ;; Ensure caller is authorized
    (asserts! (is-eq tx-sender current-admin) ERR-UNAUTHORIZED)
    (asserts! (not (is-none resource)) ERR-RESOURCE-NOT-FOUND)
    
    ;; Update resource verification status
    (map-set resources
      { resource-id: resource-id }
      (merge (unwrap! resource ERR-RESOURCE-NOT-FOUND)
        { verified: true }
      )
    )
    
    (ok true)
  )
)

;; Grant access to a restricted resource
(define-public (grant-resource-access (resource-id (string-ascii 36)) (user principal))
  (let ((resource (map-get? resources { resource-id: resource-id })))
    ;; Validate resource exists and caller is the owner
    (asserts! (not (is-none resource)) ERR-RESOURCE-NOT-FOUND)
    (asserts! (is-eq (get owner (unwrap! resource ERR-RESOURCE-NOT-FOUND)) tx-sender) ERR-UNAUTHORIZED)
    
    ;; Record the access permission
    (map-set resource-permissions
      { resource-id: resource-id, user: user }
      {
        has-access: true,
        granted-at: block-height,
        granted-by: tx-sender
      }
    )
    
    (ok true)
  )
)

;; Create a governance proposal
(define-public (create-proposal (title (string-ascii 100)) (description (string-ascii 500)) (voting-duration uint))
  (let (
    (member-info (get-member tx-sender))
    (proposal-id (var-get next-proposal-id))
  )
    ;; Validate caller is a registered member
    (asserts! (not (is-none member-info)) ERR-UNAUTHORIZED)
    
    ;; Record the proposal
    (map-set governance-proposals
      { proposal-id: proposal-id }
      {
        title: title,
        description: description,
        proposer: tx-sender,
        proposed-at: block-height,
        voting-ends-at: (+ block-height voting-duration),
        yes-votes: u0,
        no-votes: u0,
        status: "active"
      }
    )
    
    ;; Increment proposal ID
    (var-set next-proposal-id (+ proposal-id u1))
    
    (ok proposal-id)
  )
)

;; Finalize a proposal that has reached its voting deadline
(define-public (finalize-proposal (proposal-id uint))
  (let (
    (proposal (map-get? governance-proposals { proposal-id: proposal-id }))
  )
    ;; Validate proposal exists
    (asserts! (not (is-none proposal)) ERR-INVALID-PARAMETERS)
    
    (let ((proposal-info (unwrap! proposal ERR-INVALID-PARAMETERS)))
      ;; Ensure proposal voting period has ended and proposal is still active
      (asserts! (> block-height (get voting-ends-at proposal-info)) ERR-INVALID-PARAMETERS)
      (asserts! (is-eq (get status proposal-info) "active") ERR-INVALID-PARAMETERS)
      
      ;; Determine outcome and update status
      (let (
        (yes-votes (get yes-votes proposal-info))
        (no-votes (get no-votes proposal-info))
        (new-status (if (> yes-votes no-votes) "passed" "rejected"))
      )
        (map-set governance-proposals
          { proposal-id: proposal-id }
          (merge proposal-info { status: new-status })
        )
        
        (ok true)
      )
    )
  )
)

;; Transfer contract administration
(define-public (transfer-admin (new-admin principal))
  (let ((current-admin (var-get contract-admin)))
    (asserts! (is-eq tx-sender current-admin) ERR-UNAUTHORIZED)
    (var-set contract-admin new-admin)
    (ok true)
  )
)