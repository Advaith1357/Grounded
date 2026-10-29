//
//  ContactPicker.swift
//  Grounded
//
//  Choosing friends to invite from the address book. Both pieces are Apple's
//  own system UI:
//   - ContactPicker runs out-of-process, so Grounded gets only the contacts the
//     user ticks and never needs Contacts permission. Nothing is uploaded or
//     stored; the picks only pre-fill a text message.
//   - MessageComposer opens a pre-addressed message. Nothing is sent until the
//     user presses Send themselves.
//

import SwiftUI
import ContactsUI
import MessageUI

struct Invitee: Identifiable, Equatable {
    let id: String
    let name: String
    let phone: String
}

struct ContactPicker: UIViewControllerRepresentable {
    let onPick: ([Invitee]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        // Texting someone needs a number, so grey out contacts without one.
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        return picker
    }

    func updateUIViewController(_ picker: CNContactPickerViewController, context: Context) {}

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: ([Invitee]) -> Void
        init(onPick: @escaping ([Invitee]) -> Void) { self.onPick = onPick }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
            let invitees = contacts.compactMap { contact -> Invitee? in
                guard let number = contact.phoneNumbers.first?.value.stringValue else { return nil }
                let name = CNContactFormatter.string(from: contact, style: .fullName) ?? "Friend"
                return Invitee(id: contact.identifier, name: name, phone: number)
            }
            onPick(invitees)
        }
    }
}

struct MessageComposer: UIViewControllerRepresentable {
    let recipients: [String]
    let body: String
    let onFinish: () -> Void

    static var canSendText: Bool { MFMessageComposeViewController.canSendText() }

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let composer = MFMessageComposeViewController()
        composer.recipients = recipients
        composer.body = body
        composer.messageComposeDelegate = context.coordinator
        return composer
    }

    func updateUIViewController(_ composer: MFMessageComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            onFinish()
        }
    }
}
