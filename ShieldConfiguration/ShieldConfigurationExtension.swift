//
//  ShieldConfigurationExtension.swift
//  ShieldConfiguration
//
//  The interceptor screen iOS shows when a shielded app is opened. Styled to
//  match Grounded: #121212 background, Electric Yellow (#EAE04A) icon and
//  primary button.
//
//  The primary button's behavior lives in the ShieldAction extension.
//
//  ShieldConfiguration only accepts colors and plain text — there is no font
//  control — so the monospaced "[ GROUNDED ]" header is rendered into the icon
//  image, and the "[ DISCHARGE REQUIRED ]" title uses the system font.
//

import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        Self.groundedConfiguration()
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        Self.groundedConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        Self.groundedConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        Self.groundedConfiguration()
    }

    private static let background = UIColor(hex: 0x121212)
    private static let yellow = UIColor(hex: 0xEAE04A)

    private static func groundedConfiguration() -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: nil,
            backgroundColor: background,
            icon: headerIcon(),
            title: .init(text: "[ DISCHARGE REQUIRED ]", color: yellow),
            subtitle: .init(text: "Spend Voltage in Grounded to unlock.", color: UIColor(white: 0.62, alpha: 1)),
            primaryButtonLabel: .init(text: "Go to Grounded", color: background),
            primaryButtonBackgroundColor: yellow,
            secondaryButtonLabel: nil
        )
    }

    /// A yellow bolt over a monospaced "[ GROUNDED ]" label, drawn as one image.
    private static func headerIcon() -> UIImage {
        let size = CGSize(width: 220, height: 130)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let symbolConfig = UIImage.SymbolConfiguration(pointSize: 64, weight: .bold)
            if let bolt = UIImage(systemName: "bolt.fill", withConfiguration: symbolConfig)?
                .withTintColor(yellow, renderingMode: .alwaysOriginal) {
                bolt.draw(at: CGPoint(x: (size.width - bolt.size.width) / 2, y: 0))
            }

            let label = "[ GROUNDED ]" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 22, weight: .bold),
                .foregroundColor: yellow,
            ]
            let labelSize = label.size(withAttributes: attributes)
            label.draw(
                at: CGPoint(x: (size.width - labelSize.width) / 2, y: size.height - labelSize.height),
                withAttributes: attributes
            )
        }
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
