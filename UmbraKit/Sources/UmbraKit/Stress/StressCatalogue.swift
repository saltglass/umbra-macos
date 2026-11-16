/// Made-up but plausible torrents for the stress feed: Linux install images
/// and public-domain films, books and recordings, so pictures and
/// measurements look like a real list without naming anything private.
enum StressCatalogue {
  /// A kind of torrent: how its names are made, and its usual size,
  /// category, tags and tracker.
  struct Kind: Sendable {
    let names: [String]
    let variants: [String]
    let sizeMB: ClosedRange<Int>
    let category: String
    let tags: [String]
    let trackers: [String]
  }

  static let kinds: [Kind] = [
    Kind(
      names: [
        "ubuntu-24.04.1-desktop-amd64", "ubuntu-24.10-desktop-arm64", "kubuntu-24.04-desktop-amd64",
        "xubuntu-24.04-desktop-amd64", "ubuntu-24.04.1-live-server-amd64",
      ],
      variants: [".iso", "-beta.iso", "-daily.iso"], sizeMB: 2_600...6_200, category: "linux",
      tags: ["iso", "keep"], trackers: ["torrent.ubuntu.com"]),
    Kind(
      names: [
        "debian-12.7.0-amd64-netinst", "debian-12.7.0-arm64-DVD-1", "debian-live-12.7.0-amd64-kde",
        "debian-12.7.0-i386-netinst", "debian-testing-amd64-netinst",
      ],
      variants: [".iso", "-update.iso"], sizeMB: 400...4_000, category: "linux", tags: ["iso"],
      trackers: ["bttracker.debian.org"]),
    Kind(
      names: [
        "Fedora-Workstation-Live-x86_64-41", "Fedora-Server-dvd-aarch64-41",
        "Fedora-KDE-Live-x86_64-41",
        "Fedora-Silverblue-ostree-x86_64-41",
      ],
      variants: ["-1.4.iso", "-1.2.iso"], sizeMB: 2_000...3_100, category: "linux", tags: ["iso"],
      trackers: ["torrent.fedoraproject.org"]),
    Kind(
      names: [
        "archlinux-2026.11.01-x86_64", "linuxmint-22-cinnamon-64bit", "manjaro-kde-24.1.2-minimal",
        "openSUSE-Tumbleweed-DVD-x86_64-Current", "pop-os_24.04_amd64_intel",
        "kali-linux-2026.3-installer-amd64",
        "rocky-9.4-x86_64-dvd", "AlmaLinux-9.4-x86_64-minimal", "tails-amd64-6.9",
        "elementaryos-8.0-stable",
      ],
      variants: [".iso", "-r2.iso"], sizeMB: 900...4_700, category: "linux", tags: ["iso"],
      trackers: ["tracker.opentrackr.org", "tracker.archlinux.org", ""]),
    Kind(
      names: [
        "Night of the Living Dead (1968)", "Metropolis (1927)", "Nosferatu (1922)",
        "The General (1926)",
        "The Cabinet of Dr. Caligari (1920)", "His Girl Friday (1940)", "Charade (1963)",
        "Detour (1945)",
        "Plan 9 from Outer Space (1957)", "The Little Shop of Horrors (1960)",
        "Sherlock Jr. (1924)",
        "A Trip to the Moon (1902)", "The Kid (1921)", "Carnival of Souls (1962)",
      ],
      variants: [" 1080p", " 720p", " restored", " 4K remaster"], sizeMB: 700...14_000,
      category: "films", tags: ["public-domain", "4k", "archive"],
      trackers: ["bt1.archive.org", "bt2.archive.org"]),
    Kind(
      names: [
        "Big Buck Bunny", "Sintel", "Tears of Steel", "Elephants Dream", "Cosmos Laundromat",
        "Spring",
        "Agent 327 Operation Barbershop", "Caminandes Llamigos",
      ],
      variants: [" 1080p", " 4K", " 60fps", " (Blender Open Movie)"], sizeMB: 200...6_000,
      category: "films", tags: ["open-movie", "4k"], trackers: ["tracker.opentrackr.org", ""]),
    Kind(
      names: [
        "Project Gutenberg - Moby Dick", "Project Gutenberg - Pride and Prejudice",
        "Project Gutenberg - Complete Shakespeare", "Project Gutenberg - War and Peace",
        "LibriVox - The Time Machine", "LibriVox - Dracula", "LibriVox - Frankenstein",
      ],
      variants: [" (EPUB)", " (MP3 64kbps)", " (plain text)"], sizeMB: 2...900, category: "books",
      tags: ["public-domain"], trackers: ["bt1.archive.org"]),
    Kind(
      names: [
        "NASA Apollo 11 Mission Audio", "NASA Hubble Deep Field Images",
        "Prelinger Archives Collection",
        "Internet Archive - 78rpm Records Sampler", "Musopen - Beethoven Symphonies",
        "Musopen - Chopin Nocturnes", "Wikipedia dump enwiki-20261101-pages-articles",
      ],
      variants: [" vol 1", " vol 2", " FLAC", ""], sizeMB: 300...22_000, category: "",
      tags: ["archive", "seed-long"], trackers: ["bt1.archive.org", "tracker.opentrackr.org"]),
  ]

  /// Plain-English reasons, as Umbra words them, for the error-ish states.
  static let errors = [
    "The disk is full: there's no room left to write in /Volumes/Media.",
    "The tracker says this torrent isn't registered with it.",
    "Umbra can't write to /Volumes/Media/Downloads: permission denied.",
  ]
  static let missing =
    "The files aren't in /Users/Shared/Downloads any more: they were moved or deleted outside Umbra."
  static let seedGoal = "Stopped at its seed ratio of 2"
}
