# Music-Collection-Cleanup
Music Collection Cleanup – Stage One Summary At project kickoff, the music collection consisted of ................

Digitial Music Collection Upgrade and simplification with chatGPT June 2025
Inbox

Roy Williams rwillia2001@gmail.com
Wed, Jul 2, 1023 AM (2 days ago)
to me

✅ Of course — here’s a concise ~300-word project summary you can copy into your notes or documentation

Music Collection Cleanup – Stage One Summary
At project kickoff, the music collection consisted of thousands of FLAC and MP3 files with inconsistent folder structures, metadata gaps, and many duplicate or orphaned items. Playback across Plex and PowerAmp was inconsistent due to mixed tags, inconsistent albumartist fields, and an unstructured folder hierarchy. Path length exceeding limit was a big problem and meant that a lot of files would not transfer to the already long path length for the MUSIC folder on Android.

The collection was reorganized on the main storage volume D:\av_media\audio_media with two distinct mount points

FLAC original and cleaned
D:\av_media\audio_media\MyMusic_flac_redo

MP3 flattened and organized
D:\av_media\audio_media\MyMusic_mp3_flat

FLAC flattened (final mirror)
D:\av_media\audio_media\MyMusic_FLAC_Flat
==================================

The MyM folder contains the mp3 files which are transfered to the samsung S24+ phone and played with PowerAmp. Works just great and no problems with path length.

Here:  “internal storage/MUSIC” in Samsung’s file browser, that maps to: "/storage/emulated/0/Music/" in real "linux style" terms.

==================================

Two key PowerShell scripts were created and refined to support this:   
(1) FlattenAndTranscodeMusic3.ps1 
Handled flattening FLAC files to MP3 (CBR 320kbps),  
Applied consistent tag fallback logic (Composer, Album, Performer)
Created a flattened folder structure of
Composer-Album[Performer]Track.mp3
Skipped re-encoding if the MP3 was newer than the FLAC
==============================================
(2) FlattenFlacCollection_v2.ps1

Used the same logic as above
Flattened FLACs directly (no transcoding) into the same folder structure
Ensured correct composer/album/performer fallback handling

===================================================

Consistent with Plex and PowerAmp needs

Key metadata corrections were made with Mp3tag to repair missing tags (especially for classical and compilation albums), and fallback logic was enhanced to respect COMPILATION, AlbumArtist, and album_artist fields to fix ambiguities. 

The genre divider was changed from / to # using an Action in Mp3tag :  UniversalSafeTagCleaner_Pro. 
Genre upper/lower case corrected by using filter and field corrections -- F3 for filter and Alt-6 for fields corrections.

PLEX (and winamp?) will split genre fields on the / which makes a big mess of the classical music genre system. Needs to be a single ID line.

Overall, the new collection is now neatly flattened, reliable, and tag-consistent, with good browse performance in Plex and PowerAmp. This gives a solid foundation for Stage Two building a simple intake workflow for new CDs and new FLACMP3s, plus implementing an automatic backup strategy for permanent preservation.

If you’d like, I can help you design Stage Two next — just say “yes, let’s plan Stage Two” whenever you’re ready! 🚀
