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
        walkOwner = walk.owner                                            // the entity that owns the walk animation
        walkAnimation = walk.animation                                    // the walk clip itself

        petTracks = Self.animationsToPlay(in: pet)                        // skeleton on its own entity + each heart on its own entity
        guard !petTracks.isEmpty else { throw SwapError.noAnimation(Self.petFileName) } // nothing to play
        var longest: TimeInterval = 0                                     // the longest reaction animation so far
        for track in petTracks {                                          // look at every reaction animation
            let duration = track.animation.definition.duration            // its length in seconds
            if duration > longest {                                       // longer than the longest so far?
                longest = duration                                        // remember it
            }
        }
        petDuration = longest                                             // the longest one decides the length
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
            swapToPet()                                                   // then swap right away
            return                                                        // nothing more to do here
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
        updateSubscription?.cancel()                                      // stop the step check
        updateSubscription = nil                                          // and forget it
        guard let pet = petModel, !petTracks.isEmpty,                     // loaded?
              let scene = walkModel.scene else {                          // in a scene? (needed to hear when it ends)
            state = .walking                                              // no: stay walking
            return                                                        // don't swap
        }
        pet.transform = walkModel.transform                               // copy where the walking cat is right now
        walkModel.isEnabled = false                                       // hide the walking cat
        pet.isEnabled = true                                              // show the pet cat FIRST…
        petControllers = []                                               // start with an empty list
        for track in petTracks {                                          // …THEN start skeleton + hearts from 0 s
            let controller = track.owner.playAnimation(track.animation, transitionDuration: 0, startsPaused: false) // play one
            petControllers.append(controller)                             // remember it (to count "finished" and to stop it)
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
        completedSubscription?.cancel()                                   // stop listening for "finished"
        completedSubscription = nil                                       // and forget it
        updateSubscription?.cancel()                                      // stop the safety timer
        updateSubscription = nil                                          // and forget it
        walkModel.isEnabled = true                                        // show the walking cat
        petModel?.isEnabled = false                                       // hide the pet cat
        for controller in petControllers {                                // every reaction animation
            controller.stop()                                             // release it
        }
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
        var owners: [Entity] = []                                         // entities that list animations
        for entity in everything {                                        // look at every entity
            if !entity.availableAnimations.isEmpty {                      // it has at least one animation
                owners.append(entity)                                     // keep it
            }
        }
        var chosen: [Entity] = []                                         // entities we will play on

        // 1. The skeleton: start at each entity that holds a skeleton pose and go up to the nearest animation.
        for skeleton in everything {                                      // look at every entity
            if !skeleton.components.has(SkeletalPosesComponent.self) {    // not holding a skeleton pose?
                continue                                                  // skip it
            }
            var current: Entity? = skeleton                               // start at the skeleton entity…
            while let entity = current {                                  // …and walk up the parents
                if !entity.availableAnimations.isEmpty {                  // this one has an animation
                    break                                                 // stop here
                }
                if entity === root {                                      // reached the top of the file
                    break                                                 // stop here
                }
                current = entity.parent                                   // go one level up
            }
            if let owner = current {                                      // we stopped on an entity
                if !owner.availableAnimations.isEmpty {                   // and it really has an animation
                    if !Self.list(chosen, contains: owner) {              // not chosen yet
                        chosen.append(owner)                              // play the skeleton here
                    }
                }
            }
        }

        // 2. The rest (the hearts): the deepest entities with an animation, not on the skeleton's branch.
        for owner in owners {                                             // every entity that has an animation
            var animatedBelow = false                                     // does any child also have one?
            for child in allEntities(in: owner).dropFirst() {             // every entity below this one
                if !child.availableAnimations.isEmpty {                   // this child has an animation
                    animatedBelow = true                                  // so `owner` is not the deepest
                    break                                                 // no need to look further
                }
            }

            var skeletonRelated = false                                   // same branch as a skeleton we already play?
            for picked in chosen {                                        // every entity chosen so far
                if picked === owner || isAncestor(picked, of: owner) || isAncestor(owner, of: picked) {
                    skeletonRelated = true                                // same branch
                    break                                                 // no need to look further
                }
            }

            if !animatedBelow && !skeletonRelated {                       // a leaf of its own (a heart)
                chosen.append(owner)                                      // play it
            }
        }

        // 3. One animation per entity (two on one entity would replace each other).
        var result: [(owner: Entity, animation: AnimationResource)] = []  // what we will play
        for owner in chosen {                                             // every chosen entity
            let first = owner.availableAnimations[0]                      // its first animation
            result.append((owner: owner, animation: first))               // add it to the list
        }
        return result                                                     // skeleton + hearts
    }

    /// true when `entity` is already in `list` (same object, not just same name).
    private static func list(_ list: [Entity], contains entity: Entity) -> Bool {
        for item in list {                                                // every entity in the list
            if item === entity {                                          // the very same object
                return true                                               // found it
            }
        }
        return false                                                      // not in the list
    }

    /// The entity itself and all of its descendants (depth-first).
    private static func allEntities(in entity: Entity) -> [Entity] {
        var result: [Entity] = [entity]                                   // me first
        for child in entity.children {                                    // then each child…
            result += allEntities(in: child)                              // …with its whole tree
        }
        return result                                                     // me + everything below me
    }

    /// true when `ancestor` is a parent, grandparent… of `entity`.
    private static func isAncestor(_ ancestor: Entity, of entity: Entity) -> Bool {
        var current = entity.parent                                       // start one level up
        while let parent = current {                                      // walk up to the top
            if parent === ancestor {                                      // is this the one?
                return true                                               // found it
            }
            current = parent.parent                                       // keep going up
        }
        return false                                                      // not above it
    }

    /// Every animation in this entity and all of its children (depth-first, the entity itself first).
    private static func allAnimations(in entity: Entity) -> [(owner: Entity, animation: AnimationResource)] {
        var found: [(owner: Entity, animation: AnimationResource)] = []   // nothing found yet
        for animation in entity.availableAnimations {                     // this entity's own animations
            found.append((owner: entity, animation: animation))           // add each one
        }
        for child in entity.children {                                    // then look deeper
            found += allAnimations(in: child)                             // add the children's animations
        }
        return found                                                      // may be empty
    }
}
