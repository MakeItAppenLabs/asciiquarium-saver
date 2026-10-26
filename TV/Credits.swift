/// The README's Credits section, plus the license and where to get the source, which the GPL asks
/// for. tvOS can't open web pages, so the address is shown as text.
enum Credits {
    static let paragraphs: [String] = [
        "Asciiquarium stands on a lot of other people's work.",
        "Kirk Baucom wrote the original asciiquarium and the Term::Animation engine it runs on.",
        "Joan Stark drew most of the ASCII art.",
        "Claudio Matsuoka added the new species, backported from his Asciiquarium live wallpaper for Android.",
        "driechers contributed the yellow submarine and restored elements that had been lost.",
        "Carl Pilcher drew the ASCII art for the submarine.",
        "robert1003 implemented the swordfish, and ctr drew its ASCII art.",
        "polettix assembled the contributions into one program.",
        "Mohammad Abu Mattar wrote the Python port, used here as a cross-check.",
        """
        The 1.6 source also credits UndeadLeech (background color and transparency), kronos-chenchang \
        (the opening castle door and a swordfish fix), Phani Rithvij (screensaver mode), Steven Ward (bug \
        fixes and consistency patches), Hugh Davenport (the new creature mode), Viggo Lekdorf (the \
        transparency toggle), Marcin Kulik (a fix for orphaned fishhook entities) and Jared Still (the \
        jellyfish).
        """,
        """
        Asciiquarium is free software under the GNU General Public License, version 3 or later. \
        Source code: https://github.com/MakeItAppenLabs/asciiquarium-saver
        """,
    ]
}
