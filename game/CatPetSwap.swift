//
//  CatPetSwap.swift
//
//  Swaps your walking cat (cat.usdz) for the pet reaction (cat_sit_headturn_hearts.usdz) and back.
//
//  Flow:  walking → pet() → the cat finishes its current step → swap to the pet cat →
//         sit down, head tilt (left, then right) with hearts, rise (4.73 s) → swap back → walk again.
//
//  Why wait for the step to finish: both files share one pose — the first frame of the walk.
//  The pet file starts and ends on it, so swapping exactly there shows no jump.
//
//  Which animations are played (see animationsToPlay):
//  RealityKit lists copies of the pet file's animations on many entities. Only the skeleton's own copy
//  (on the entity that holds the skeleton pose) and each heart's own copy are played. Copies on parent
//  entities can't find their target ("Cannot find a BindPoint…"), and two animations on one entity
//  replace each other — both made the cat freeze in earlier versions.
//
//  Requires iOS 18+ (async Entity(named:) loader, SkeletalPosesComponent).
//

import RealityKit                                                         // Entity, AnimationResource, scene events
import Combine                                                            // Cancellable (keeps event subscriptions alive)
import Foundation                                                         // TimeInterval

@MainActor                                                                // RealityKit objects are used on the main actor
final class CatPetSwap {

    // MARK: - Settings

    static let petFileName = "cat_sit_headturn_hearts"                    // pet reaction file in the app bundle (no ".usdz")
    static let walkLoopDuration: TimeInterval = 100.0 / 120.0             // one walk cycle in cat.usdz: 100 frames at 120 fps = 0.83 s
    static let safetyMargin: TimeInterval = 0.5                           // extra time before the safety timer ends the reaction

    // MARK: - Errors

    enum SwapError: Error {                                               // problems load() can report
        case walkingCatHasNoParent                                        // add the walking cat to your anchor/scene before load()
        case noAnimation(String)                                          // a file had no animation to play
    }

    // MARK: - State

    enum State { case walking, waitingForStep, petting }                  // what the cat is doing right now
    private(set) var state: State = .walking                              // starts walking
    var isReacting: Bool { state == .petting }                            // true while the pet cat is shown: pause your movement code

    // MARK: - Entities and animations

    let walkModel: Entity                                                 // your cat.usdz entity (already in the scene)
    private var petModel: Entity?                                         // the cat_sit_headturn_hearts entity (made in load())
    private var walkOwner: Entity?                                        // entity inside cat.usdz that owns the walk animation
    private var walkAnimation: AnimationResource?                         // the walk clip
    private var walkController: AnimationPlaybackController?              // controls the playing walk
    private var petTracks: [(owner: Entity, animation: AnimationResource)] = [] // what to play: skeleton + each heart
    private var petControllers: [AnimationPlaybackController] = []        // the reaction animations while they play
    private var petDuration: TimeInterval = 0                             // length of the longest reaction animation (≈ 4.73 s)

    // MARK: - Subscriptions and timers

    private var updateSubscription: Cancellable?                          // per-frame check: step end (before) or safety timer (during)
    private var completedSubscription: Cancellable?                       // fires each time a reaction animation finishes
    private var lastPhase: TimeInterval = 0                               // position inside the walk cycle, last frame
    private var waited: TimeInterval = 0                                  // how long we've been waiting for the step to end
    private var finishedCount = 0                                         // how many reaction animations have finished
    private var reactionTime: TimeInterval = 0                            // time since the reaction started (safety timer)

    init(walkModel: Entity) {
        self.walkModel = walkModel                                        // remember your walking cat
    }

    // MARK: - Public

    /// Loads the pet file once and places it, hidden, exactly where the walking cat is.
    func load() async throws {
        guard let parent = walkModel.parent else { throw SwapError.walkingCatHasNoParent } // same parent = same coordinate space
        let pet = try await Entity(named: Self.petFileName)               // load cat_sit_headturn_hearts.usdz from the app bundle
        parent.addChild(pet)                                              // sits next to the walking cat in the scene
        pet.transform = walkModel.transform                               // same position, rotation and scale
        pet.isEnabled = false                                             // hidden until the cat is petted
        petModel = pet                                                    // keep it

        guard let walk = Self.allAnimations(in: walkModel).first else {   // the walk: first animation in cat.usdz
            throw SwapError.noAnimation("cat.usdz")
        }
        walkOwner = walk.owner; walkAnimation = walk.animation            // where the walk lives

        petTracks = Self.animationsToPlay(in: pet)                        // skeleton on its own entity + each heart on its own entity
        guard !petTracks.isEmpty else { throw SwapError.noAnimation(Self.petFileName) } // nothing to play
        petDuration = petTracks.map { $0.animation.definition.duration }.max() ?? 0 // the longest one decides the length
    }

    /// Starts (or restarts) the walk from its first frame, looping forever.
    /// Use this instead of your own playAnimation(...repeat()) call, so the swap knows where the step is.
    func startWalking() {
        guard let owner = walkOwner, let anim = walkAnimation else { return } // load() must have run
        walkController?.stop()                                            // stop any previous walk playback
        walkController = owner.playAnimation(anim.repeat(), transitionDuration: 0, startsPaused: false) // loop the walk
    }

    /// Call this when your hand tracking decides the cat is being petted.
    func pet() {
        guard state == .walking, !petTracks.isEmpty else { return }       // ignore while already reacting, or before load()
        state = .waitingForStep                                           // let the cat finish its current step first
        guard walkController != nil, let scene = walkModel.scene else {   // can't follow the step (walk not started by us)?
            swapToPet(); return                                           // then swap right away
        }
        lastPhase = walkPhase()                                           // where we are in the step now
        waited = 0                                                        // start the safety timer
        updateSubscription = scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            MainActor.assumeIsolated { self?.checkStepFinished(deltaTime: event.deltaTime) } // check every frame
        }
    }

    /// Call this after your code moves the walking cat while the reaction is showing
    /// (for example the Reset Cat button), so the sitting cat moves with it and nothing jumps later.
    func matchPetToWalk() {
        petModel?.transform = walkModel.transform                         // same position, rotation and scale as the walking cat
    }

    // MARK: - Private

    /// Position inside the current 0.83 s walk cycle.
    private func walkPhase() -> TimeInterval {
        guard let controller = walkController else { return 0 }           // no walk playing
        return controller.time.truncatingRemainder(dividingBy: Self.walkLoopDuration) // time within this cycle
    }

    /// When the cycle wraps around, the walking cat is on its first pose = the pet file's first pose.
    private func checkStepFinished(deltaTime: TimeInterval) {
        waited += deltaTime                                               // time spent waiting
        let phase = walkPhase()                                           // current position in the cycle
        if phase < lastPhase || waited > Self.walkLoopDuration + 0.1 {    // wrapped (or safety timeout)
            swapToPet()                                                   // swap now
        } else {
            lastPhase = phase                                             // keep waiting
        }
    }

    /// Hide the walking cat, show the pet cat on the same spot, then play the reaction animations.
    private func swapToPet() {
        updateSubscription?.cancel(); updateSubscription = nil            // stop the step check
        guard let pet = petModel, !petTracks.isEmpty,                     // loaded?
              let scene = walkModel.scene else {                          // in a scene? (needed to hear when it ends)
            state = .walking; return                                      // no: stay walking
        }
        pet.transform = walkModel.transform                               // copy where the walking cat is right now
        walkModel.isEnabled = false                                       // hide the walking cat
        pet.isEnabled = true                                              // show the pet cat FIRST…
        petControllers = petTracks.map { track in                         // …THEN start skeleton + hearts from 0 s
            track.owner.playAnimation(track.animation, transitionDuration: 0, startsPaused: false)
        }
        finishedCount = 0                                                 // none finished yet
        reactionTime = 0                                                  // safety timer starts at 0
        completedSubscription = scene.subscribe(to: AnimationEvents.PlaybackCompleted.self) { [weak self] _ in
            MainActor.assumeIsolated { self?.reactionAnimationFinished() } // one reaction animation finished
        }
        updateSubscription = scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            MainActor.assumeIsolated { self?.checkReactionTimeout(deltaTime: event.deltaTime) } // safety timer
        }
        state = .petting                                                  // your movement code should pause now
    }

    /// Counts finished reaction animations; when all are done, go back to walking.
    /// (The walk loops forever and never "finishes", so every completion here belongs to the reaction.)
    private func reactionAnimationFinished() {
        guard state == .petting else { return }                           // only while reacting
        finishedCount += 1                                                // one more finished
        if finishedCount >= petControllers.count {                        // all finished?
            swapToWalk()                                                  // back to walking
        }
    }

    /// Safety net: if a "finished" event never arrives, end the reaction a little after its length.
    private func checkReactionTimeout(deltaTime: TimeInterval) {
        reactionTime += deltaTime                                         // time since the reaction started
        if reactionTime > petDuration + Self.safetyMargin {               // clearly past the end
            swapToWalk()                                                  // back to walking
        }
    }

    /// Hide the pet cat, show the walking cat, walk again from the first frame.
    private func swapToWalk() {
        guard state == .petting else { return }                           // run once per reaction
        completedSubscription?.cancel(); completedSubscription = nil      // stop listening for "finished"
        updateSubscription?.cancel(); updateSubscription = nil            // stop the safety timer
        walkModel.isEnabled = true                                        // show the walking cat
        petModel?.isEnabled = false                                       // hide the pet cat
        petControllers.forEach { $0.stop() }                              // release the finished reaction animations
        petControllers.removeAll()                                        // ready for the next pet
        startWalking()                                                    // frame 0 of the walk = the pose the reaction ended on
        state = .walking                                                  // movement can continue
    }

    /// Picks which animations to play so every part of the pet file moves exactly once:
    /// - skeleton (sit + head tilt): the animation on the entity that holds the skeleton pose
    ///   (it has a SkeletalPosesComponent), or on its nearest parent that has one;
    /// - everything else (the 5 hearts): the animation on the deepest entities that have one.
    private static func animationsToPlay(in root: Entity) -> [(owner: Entity, animation: AnimationResource)] {
        let everything = allEntities(in: root)                            // the loaded root and every child, grandchild…
        let owners = everything.filter { !$0.availableAnimations.isEmpty } // entities that list animations
        var chosen: [Entity] = []                                         // entities we will play on

        for skeleton in everything where skeleton.components.has(SkeletalPosesComponent.self) { // entities holding a skeleton pose
            var current: Entity? = skeleton                               // start at the skeleton entity…
            while let entity = current, entity.availableAnimations.isEmpty, entity !== root {
                current = entity.parent                                   // …and go up until an entity has an animation
            }
            if let owner = current, !owner.availableAnimations.isEmpty,
               !chosen.contains(where: { $0 === owner }) {
                chosen.append(owner)                                      // play the skeleton here
            }
        }

        for owner in owners {                                             // the rest: deepest entities with an animation
            let animatedBelow = allEntities(in: owner).dropFirst().contains { !$0.availableAnimations.isEmpty } // any animated child?
            let skeletonRelated = chosen.contains {                       // same branch as a skeleton we already play?
                $0 === owner || isAncestor($0, of: owner) || isAncestor(owner, of: $0)
            }
            if !animatedBelow && !skeletonRelated { chosen.append(owner) } // a leaf of its own (a heart): play it
        }

        return chosen.map { (owner: $0, animation: $0.availableAnimations[0]) } // one per entity (two would replace each other)
    }

    /// The entity itself and all of its descendants (depth-first).
    private static func allEntities(in entity: Entity) -> [Entity] {
        [entity] + entity.children.flatMap { allEntities(in: $0) }        // me, then my children's trees
    }

    /// true when `ancestor` is a parent, grandparent… of `entity`.
    private static func isAncestor(_ ancestor: Entity, of entity: Entity) -> Bool {
        var current = entity.parent                                       // start one level up
        while let parent = current {                                      // walk up to the top
            if parent === ancestor { return true }                        // found it
            current = parent.parent                                       // keep going up
        }
        return false                                                      // not above it
    }

    /// Every animation in this entity and all of its children (depth-first, the entity itself first).
    private static func allAnimations(in entity: Entity) -> [(owner: Entity, animation: AnimationResource)] {
        var found = entity.availableAnimations.map { (owner: entity, animation: $0) } // this entity's animations
        for child in entity.children {                                    // then look deeper
            found += allAnimations(in: child)                             // add the children's animations
        }
        return found                                                      // may be empty
    }
}
