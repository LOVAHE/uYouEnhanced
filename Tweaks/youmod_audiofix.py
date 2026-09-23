from pathlib import Path

OLD_BLOCK = r'''    NSArray *availableTracks = [switchcon valueForKey:@"_availableAudioTracks"];
    if (!availableTracks || availableTracks.count == 0) return;
    YTIAudioTrack *matchedTrack = nil;

    if (INTFORVAL(AudioTrack) == 1) {
        // Loop for all tracks
        for (YTIAudioTrack *track in availableTracks) {
            if ([track.id_p hasSuffix:@".4"]) {
                matchedTrack = track;
                break;
            }
        }
    } else if (INTFORVAL(AudioTrack) == 2) {
        // Loop for all tracks
        for (YTIAudioTrack *track in availableTracks) {
            if ([track.id_p hasPrefix:userTargetLang]) {
                matchedTrack = track;
                break;
            }
        }

        // Check if it's dubbed
        if (matchedTrack && [matchedTrack isAutoDubbed] && IS_ENABLED(NoDubbedAudioTrack)) matchedTrack = nil;

        if (!matchedTrack && IS_ENABLED(NoDubbedAudioTrack)) {
            for (YTIAudioTrack *track in availableTracks) {
                if ([track.id_p hasSuffix:@".4"]) {
                    matchedTrack = track;
                    break;
                }
            }
        }
    }

    // If found, change to it
    if (matchedTrack) {
'''

NEW_BLOCK = r'''    NSArray *availableTracks = [switchcon valueForKey:@"_availableAudioTracks"];
    // Do not force a switch when there is nothing to switch to. Re-selecting the
    // sole track while the 21.36+ player is settling can invalidate playback.
    if (!availableTracks || availableTracks.count <= 1) return;
    YTIAudioTrack *matchedTrack = nil;

    if (INTFORVAL(AudioTrack) == 1) {
        // Prefer YouTube's original-track marker, never an auto-dubbed track.
        for (YTIAudioTrack *track in availableTracks) {
            if ([track.id_p hasSuffix:@".4"] && ![track isAutoDubbed]) {
                matchedTrack = track;
                break;
            }
        }

        // If the marker changes, accept a non-dubbed default track.
        if (!matchedTrack) {
            for (YTIAudioTrack *track in availableTracks) {
                if (![track isAutoDubbed] && track.audioIsDefault) {
                    matchedTrack = track;
                    break;
                }
            }
        }

        // Last safe fallback: switch only if there is exactly one non-dubbed track.
        if (!matchedTrack) {
            YTIAudioTrack *onlyNonDubbed = nil;
            NSUInteger nonDubbedCount = 0;
            for (YTIAudioTrack *track in availableTracks) {
                if (![track isAutoDubbed]) {
                    onlyNonDubbed = track;
                    nonDubbedCount++;
                }
            }
            if (nonDubbedCount == 1) matchedTrack = onlyNonDubbed;
        }
    } else if (INTFORVAL(AudioTrack) == 2) {
        for (YTIAudioTrack *track in availableTracks) {
            if ([track.id_p hasPrefix:userTargetLang]) {
                matchedTrack = track;
                break;
            }
        }

        if (matchedTrack && [matchedTrack isAutoDubbed] && IS_ENABLED(NoDubbedAudioTrack))
            matchedTrack = nil;

        if (!matchedTrack && IS_ENABLED(NoDubbedAudioTrack)) {
            for (YTIAudioTrack *track in availableTracks) {
                if ([track.id_p hasSuffix:@".4"] && ![track isAutoDubbed]) {
                    matchedTrack = track;
                    break;
                }
            }
        }
    }

    // Never force AI dubbing. Avoid redundant switching when the desired track
    // is already YouTube's default track.
    if (matchedTrack && ![matchedTrack isAutoDubbed] && !matchedTrack.audioIsDefault) {
'''

def replace_once(path, old, new):
    p = Path(path)
    s = p.read_text()
    if old not in s:
        raise SystemExit(f"expected block missing in {path}")
    p.write_text(s.replace(old, new, 1))

for path in ("YouMod/Files/Player.x", "YouMod/Files/Shorts.x"):
    replace_once(path, OLD_BLOCK, NEW_BLOCK)

replace_once(
    "YouMod/Files/Player.x",
    'if (INTFORVAL(AudioTrack) != 0) [playerviewController performSelector:@selector(YouModAutoAudioTrack) withObject:nil afterDelay:0.1];',
    'if (INTFORVAL(AudioTrack) != 0) [playerviewController performSelector:@selector(YouModAutoAudioTrack) withObject:nil afterDelay:0.75];',
)

replace_once(
    "YouMod/Files/Shorts.x",
    'if (INTFORVAL(AudioTrack) != 0) [self performSelector:@selector(YouModAutoAudioTrack:) withObject:main afterDelay:0.5];',
    'if (INTFORVAL(AudioTrack) != 0) [self performSelector:@selector(YouModAutoAudioTrack:) withObject:main afterDelay:0.75];',
)

replace_once(
    "YouMod/Files/Settings.x",
    '        ForwardSeconds: @10.0,\n',
    '        ForwardSeconds: @10.0,\n        AudioTrack: @1,\n        NoDubbedAudioTrack: @YES,\n',
)
