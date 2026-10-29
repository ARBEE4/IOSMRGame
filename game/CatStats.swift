//
//  CatStats.swift
//  game
//
//  Created by Kwan Chi Chung on 2/10/2026.
//

import Foundation   // Date, TimeInterval, UserDefaults, Calendar
import Observation  // @Observable

// Every mood setting in one place, same idea as HandTrackingTuning
enum CatStatsTuning {
    static let moodMax: Double = 100                // value of a full bar
    static let moodStart: Double = 80               // mood on the very first launch
    static let decayAmount: Double = 1              // mood lost per step
    static let decayInterval: TimeInterval = 60     // seconds per step: 60 = every minute, 3600 = every hour
    static let petGain: Double = 10                 // mood gained when a pet counts
    static let moodPetCooldown: TimeInterval = 300  // NEW (A): counted pets must be at least 5 minutes apart
    static let dailyPetLimit = 5                    // NEW (C): at most 5 pets count per calendar day
}

@MainActor   // only used on the main thread (SwiftUI and RealityKit's update event)
@Observable  // views that read these values redraw by themselves when they change
final class CatStats {
    private(set) var mood: Double         // 0...moodMax; any code can read it, only this class can change it
    private(set) var petsTodayCount: Int  // NEW (C): how many pets counted on lastPetDate's day
    private var lastDecayDate: Date       // the moment decay has been counted up to
    private var lastPetDate: Date?        // when a pet last COUNTED; nil = never (used by both A and C)

    // UserDefaults keys, written once so a typo can't split one value into two
    private enum Key {
        static let mood = "catStats.mood"                      // stores a Double
        static let petsTodayCount = "catStats.petsTodayCount"  // NEW (C): stores an Int
        static let lastDecayDate = "catStats.lastDecayDate"    // stores a Date
        static let lastPetDate = "catStats.lastPetDate"        // stores a Date
    }

    init() {
        let defaults = UserDefaults.standard                    // shortcut to the app's saved-values store

        // ── 1. mood ──
        let savedMoodValue = defaults.object(forKey: Key.mood)  // Any?: whatever was saved, or nil if never saved
        if let savedMood = savedMoodValue as? Double {          // was something saved, and is it a Double?
            mood = savedMood                                    // yes → use the saved mood
        } else {                                                // no → first launch
            mood = CatStatsTuning.moodStart                     // start at 80
        }

        // ── 2. petsTodayCount ──
        let savedPetsValue = defaults.object(forKey: Key.petsTodayCount)  // the saved count, or nil if never saved
        if let savedPets = savedPetsValue as? Int {             // was a whole number saved?
            petsTodayCount = savedPets                          // yes → use the saved count
        } else {                                                // no → first launch
            petsTodayCount = 0                                  // no pets have counted yet
        }

        // ── 3. lastDecayDate ──
        var isFirstLaunch = false                               // becomes true if no start time was saved
        let savedDecayValue = defaults.object(forKey: Key.lastDecayDate)  // the saved start time, or nil
        if let savedDecayDate = savedDecayValue as? Date {      // was a date saved?
            lastDecayDate = savedDecayDate                      // yes → continue from the saved start time
        } else {                                                // no → first launch
            lastDecayDate = .now                                // decay starts counting from this moment
            isFirstLaunch = true                                // remember that this was the first launch
        }

        // ── 4. lastPetDate ──
        let savedPetDateValue = defaults.object(forKey: Key.lastPetDate)  // the saved pet date, or nil
        if let savedPetDate = savedPetDateValue as? Date {      // was a date saved?
            lastPetDate = savedPetDate                          // yes → use the saved date
        } else {                                                // no → never petted yet
            lastPetDate = nil                                   // nil means "never"
        }

        // ── 5. catch up and remember the start time ──
        applyDecay()                                            // allowed now: all 4 properties have a value
        if isFirstLaunch {                                      // nothing was saved before this launch
            save()                                              // write the start time so the next launch can find it
        }
    }

    private func save() {
        let defaults = UserDefaults.standard                        // shortcut to the app's saved-values store
        defaults.set(mood, forKey: Key.mood)                        // save mood (Double)
        defaults.set(petsTodayCount, forKey: Key.petsTodayCount)    // save petsTodayCount (Int)
        defaults.set(lastDecayDate, forKey: Key.lastDecayDate)      // save lastDecayDate (Date)
        if let petDate = lastPetDate {                              // has a pet ever counted?
            defaults.set(petDate, forKey: Key.lastPetDate)          // yes → save that date
        } else {                                                    // no pet has counted yet
            defaults.removeObject(forKey: Key.lastPetDate)          // make sure no old date stays saved
        }
    }

    func applyDecay(now: Date = .now) {
        var changed = false                                        // did mood drop at least once?
        var nextDecayDate = lastDecayDate.addingTimeInterval(CatStatsTuning.decayInterval)  // when the next step is due (last + step length)

        while now >= nextDecayDate {                               // has that moment arrived or passed?
            mood = mood - CatStatsTuning.decayAmount               // take away one step of mood
            if mood < 0 {                                          // went below empty?
                mood = 0                                           // stop at empty
            }
            lastDecayDate = nextDecayDate                          // this step is now counted
            nextDecayDate = lastDecayDate.addingTimeInterval(CatStatsTuning.decayInterval)  // the following step is due one step later
            changed = true                                         // remember that something changed
        }

        if changed {                                               // only write to disk when mood actually dropped
            save()                                                 // save mood and the new lastDecayDate
        }
    }

    @discardableResult                                 // callers are allowed to ignore the result
    func pet(now: Date = .now) -> Bool {               // true = mood went up, false = this pet didn't count
        applyDecay(now: now)                           // a. bring mood up to date first
        resetDailyCountIfNewDay(now: now)              // b. new day → counter back to 0 (must come before the check)

        if petCounts(now: now) == false {              // c. does this pet count? (rules A + C)
            return false                               //    no → mood stays the same
        }

        var newMood = mood + CatStatsTuning.petGain    // d. add the pet bonus
        if newMood > CatStatsTuning.moodMax {          //    went above full?
            newMood = CatStatsTuning.moodMax           //    stop at full
        }
        mood = newMood                                 //    store the result

        petsTodayCount = petsTodayCount + 1            // e. one more pet counted today
        lastPetDate = now                              // f. remember the moment this pet counted
        save()                                         // g. write everything to disk
        return true                                    //    tell the caller that mood went up
    }

    // NEW (C): a new calendar day starts the counter from 0 again
    private func resetDailyCountIfNewDay(now: Date) {
        if let lastDate = lastPetDate {                                        // has a pet ever counted?
            let sameDay = Calendar.current.isDate(lastDate, inSameDayAs: now)  // is that day the same calendar day as now?
            if sameDay == false {                                              // no → it's a new day
                petsTodayCount = 0                                             // reset the daily counter
                save()                                                         // save the reset
            }
        }
    }

    // NEW (A + C): only ANSWERS "does this pet count?" and never changes anything
    private func petCounts(now: Date) -> Bool {                    // answers "should this pet raise mood?"
        // Rule A: cooldown — counted pets must be at least 5 minutes apart
        if let lastDate = lastPetDate {                            // has a pet counted before? name that date lastDate
            let secondsSinceLastPet = now.timeIntervalSince(lastDate)  // how many seconds ago was it?
            if secondsSinceLastPet < CatStatsTuning.moodPetCooldown {  // less than the cooldown?
                return false                                       // too soon → doesn't count
            }
        }
        // Rule C: daily limit — at most 5 counted pets per day
        if petsTodayCount >= CatStatsTuning.dailyPetLimit {        // already reached today's limit?
            return false                                           // too many today → doesn't count
        }
        return true                                                // passed A and C → this pet counts
    }
}
