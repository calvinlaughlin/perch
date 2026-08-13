import Foundation
import PerchCore

/// Builds the config file perch writes on first run, and the full reference behind it.
///
/// **The written file is nearly empty.** An annotated dump of every setting reads as a form to be
/// filled in: it is long, most of it is irrelevant to any one person, and a file that listed
/// today's values would date badly. A short file says the honest thing instead — the defaults are
/// the product, and this file is for disagreeing with one of them.
///
/// That only works if the options are discoverable somewhere else, which is what ``reference``
/// is for. The two are not duplicates: the file is what you keep, the reference is what you
/// consult.
///
/// Lives in `PerchUI` rather than `PerchCore` because ``reference`` lists the *registered* widgets
/// and their settings, and `PerchCore` has no idea widgets exist.
@MainActor
public enum ConfigTemplate {

    /// The file written to `~/.config/perch/config` when there isn't one.
    ///
    /// Only `widget = media` is live. Everything else is absent rather than commented, so a later
    /// perch that improves a default reaches anyone who never edited the file — which, given how
    /// short it now is, is most people.
    ///
    /// Takes no registry: the widgets are no longer listed here, only in ``reference``.
    public static func starter() -> String {
        """
        # This is the configuration file for perch.
        #
        # Empty is fine. perch ships with defaults meant to be left alone, and anything you do not
        # set here follows them — including improvements to them in later versions. Add only what
        # you want to be different.
        #
        # Saved changes apply immediately; there is no restart and no reload command. A line perch
        # cannot make sense of is reported and skipped rather than taken to heart, so a typo will
        # not leave you without a notch.
        #
        # For every option, what it accepts, and its default:
        #
        #     perch +show-config --default --docs

        widget = media
        """ + "\n"
    }

    /// Every core key and every registered widget, with documentation.
    ///
    /// This is what `perch +show-config` prints. The core keys come from `ConfigSchema`, which
    /// generates them from the same table the parser uses; this adds the widgets, which only
    /// `PerchUI` knows about.
    public static func reference(
        _ config: Config = Config(),
        includeDocs: Bool = false,
        registry: WidgetRegistry = .shared
    ) -> String {
        ConfigSchema.show(config, includeDocs: includeDocs, widgets: documentation(registry))
    }

    /// Describe the registered widgets for `PerchCore`, which cannot ask the registry itself.
    private static func documentation(_ registry: WidgetRegistry) -> [WidgetDocumentation] {
        let defaults = Config()
        return registry.kinds.compactMap { kind in
            guard let description = registry.describe(kind) else { return nil }
            return WidgetDocumentation(
                kind: kind,
                summary: description.summary,
                settings: description.settings,
                isDefault: defaults.widgets.contains(kind)
            )
        }
    }
}
