import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import AlertUI

private func parseGiftSlug(from input: String) -> String {
    var raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
    if let url = URL(string: raw), let lastComponent = url.pathComponents.last, !lastComponent.isEmpty, lastComponent != "/" {
        raw = lastComponent
    }
    if let range = raw.range(of: "t.me/nft/") {
        raw = String(raw[range.upperBound...])
    }
    if let queryIndex = raw.firstIndex(of: "?") {
        raw = String(raw[..<queryIndex])
    }
    return raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
}

private func parseSlugTitleAndNumber(slug: String) -> (String, Int32) {
    let parts = slug.split(separator: "-")
    if let last = parts.last, let num = Int32(last) {
        let titleParts = parts.dropLast()
        let title = titleParts.isEmpty ? "Gift" : titleParts.map { $0.capitalized }.joined(separator: " ")
        return (title, num)
    }
    return (slug.capitalized, 1)
}

private final class FakeProfileSettingsArguments {
    let context: AccountContext
    let updateVisualPremium: (Bool) -> Void
    let updateStarsBalance: (Int64?) -> Void
    let updateTonBalance: (Double?) -> Void
    let updateMainUsername: (String?) -> Void
    let updateFakePhoneEnabled: (Bool) -> Void
    let updateFakePhone: (String) -> Void
    let updateFakePhonePriceTon: (Double) -> Void
    let updatePurchaseDate: (String?) -> Void
    let updatePublicBalanceEnabled: (Bool) -> Void
    let updatePublicBalanceAmount: (Double?) -> Void
    let updatePublicBalanceCurrency: (String) -> Void
    let updatePublicWalletAddress: (String) -> Void
    let updateOrganizationVerificationEnabled: (Bool) -> Void
    let updateOrganizationName: (String) -> Void
    let updateOrganizationDescription: (String) -> Void
    let updateRatingEnabled: (Bool) -> Void
    let updateRatingPoints: (Int64?) -> Void
    let addUsername: () -> Void
    let deleteUsername: (String) -> Void
    let addNftGiftByLink: () -> Void
    let deleteGift: (UUID) -> Void
    let openGiftConstructor: () -> Void

    init(
        context: AccountContext,
        updateVisualPremium: @escaping (Bool) -> Void,
        updateStarsBalance: @escaping (Int64?) -> Void,
        updateTonBalance: @escaping (Double?) -> Void,
        updateMainUsername: @escaping (String?) -> Void,
        updateFakePhoneEnabled: @escaping (Bool) -> Void,
        updateFakePhone: @escaping (String) -> Void,
        updateFakePhonePriceTon: @escaping (Double) -> Void,
        updatePurchaseDate: @escaping (String?) -> Void,
        updatePublicBalanceEnabled: @escaping (Bool) -> Void,
        updatePublicBalanceAmount: @escaping (Double?) -> Void,
        updatePublicBalanceCurrency: @escaping (String) -> Void,
        updatePublicWalletAddress: @escaping (String) -> Void,
        updateOrganizationVerificationEnabled: @escaping (Bool) -> Void,
        updateOrganizationName: @escaping (String) -> Void,
        updateOrganizationDescription: @escaping (String) -> Void,
        updateRatingEnabled: @escaping (Bool) -> Void,
        updateRatingPoints: @escaping (Int64?) -> Void,
        addUsername: @escaping () -> Void,
        deleteUsername: @escaping (String) -> Void,
        addNftGiftByLink: @escaping () -> Void,
        deleteGift: @escaping (UUID) -> Void,
        openGiftConstructor: @escaping () -> Void
    ) {
        self.context = context
        self.updateVisualPremium = updateVisualPremium
        self.updateStarsBalance = updateStarsBalance
        self.updateTonBalance = updateTonBalance
        self.updateMainUsername = updateMainUsername
        self.updateFakePhoneEnabled = updateFakePhoneEnabled
        self.updateFakePhone = updateFakePhone
        self.updateFakePhonePriceTon = updateFakePhonePriceTon
        self.updatePurchaseDate = updatePurchaseDate
        self.updatePublicBalanceEnabled = updatePublicBalanceEnabled
        self.updatePublicBalanceAmount = updatePublicBalanceAmount
        self.updatePublicBalanceCurrency = updatePublicBalanceCurrency
        self.updatePublicWalletAddress = updatePublicWalletAddress
        self.updateOrganizationVerificationEnabled = updateOrganizationVerificationEnabled
        self.updateOrganizationName = updateOrganizationName
        self.updateOrganizationDescription = updateOrganizationDescription
        self.updateRatingEnabled = updateRatingEnabled
        self.updateRatingPoints = updateRatingPoints
        self.addUsername = addUsername
        self.deleteUsername = deleteUsername
        self.addNftGiftByLink = addNftGiftByLink
        self.deleteGift = deleteGift
        self.openGiftConstructor = openGiftConstructor
    }
}

private enum FakeProfileSection: Int32 {
    case premiumAndStars
    case publicBalanceAndCard
    case organizationVerification
    case starRating
    case profileData
    case nftUsernames
    case profileGifts
}

private enum FakeProfileEntry: ItemListNodeEntry {
    case premiumHeader(String)
    case visualPremiumToggle(Bool)
    case starsBalanceInput(String, String)
    case tonBalanceInput(String, String)
    case premiumNotice(String)
    case publicBalanceHeader(String)
    case publicBalanceToggle(Bool)
    case publicBalanceCurrencyInput(String, String)
    case publicBalanceAmountInput(String, String)
    case publicWalletAddressInput(String, String)
    case publicBalanceNotice(String)
    case organizationVerificationHeader(String)
    case organizationVerificationToggle(Bool)
    case organizationNameInput(String, String)
    case organizationDescriptionInput(String, String)
    case organizationVerificationNotice(String)
    case starRatingHeader(String)
    case starRatingToggle(Bool)
    case starRatingPointsInput(String, String)
    case starRatingNotice(String)
    case profileDataHeader(String)
    case fakeMainUsernameInput(String, String)
    case fakePhoneToggle(Bool)
    case fakePhoneInput(String, String)
    case fakePhonePriceInput(String, String)
    case fakePurchaseDateInput(String, String)
    case profileDataNotice(String)
    case nftUsernamesHeader(String)
    case addUsernameAction(String)
    case nftUsernameItem(index: Int, username: String, priceTon: Double)
    case nftUsernamesNotice(String)
    case giftsHeader(String)
    case addNftGiftAction(String)
    case giftConstructorAction(String)
    case giftItem(index: Int, id: UUID, title: String, subtitle: String)
    case giftsNotice(String)

    var section: ItemListSectionId {
        switch self {
        case .premiumHeader, .visualPremiumToggle, .starsBalanceInput, .tonBalanceInput, .premiumNotice:
            return FakeProfileSection.premiumAndStars.rawValue
        case .publicBalanceHeader, .publicBalanceToggle, .publicBalanceCurrencyInput, .publicBalanceAmountInput, .publicWalletAddressInput, .publicBalanceNotice:
            return FakeProfileSection.publicBalanceAndCard.rawValue
        case .organizationVerificationHeader, .organizationVerificationToggle, .organizationNameInput, .organizationDescriptionInput, .organizationVerificationNotice:
            return FakeProfileSection.organizationVerification.rawValue
        case .starRatingHeader, .starRatingToggle, .starRatingPointsInput, .starRatingNotice:
            return FakeProfileSection.starRating.rawValue
        case .profileDataHeader, .fakeMainUsernameInput, .fakePhoneToggle, .fakePhoneInput, .fakePhonePriceInput, .fakePurchaseDateInput, .profileDataNotice:
            return FakeProfileSection.profileData.rawValue
        case .nftUsernamesHeader, .addUsernameAction, .nftUsernameItem, .nftUsernamesNotice:
            return FakeProfileSection.nftUsernames.rawValue
        case .giftsHeader, .addNftGiftAction, .giftConstructorAction, .giftItem, .giftsNotice:
            return FakeProfileSection.profileGifts.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .premiumHeader: return 1000
        case .visualPremiumToggle: return 1001
        case .starsBalanceInput: return 1002
        case .tonBalanceInput: return 1003
        case .premiumNotice: return 1004
        case .publicBalanceHeader: return 1500
        case .publicBalanceToggle: return 1501
        case .publicBalanceCurrencyInput: return 1502
        case .publicBalanceAmountInput: return 1503
        case .publicWalletAddressInput: return 1504
        case .publicBalanceNotice: return 1505
        case .organizationVerificationHeader: return 1600
        case .organizationVerificationToggle: return 1601
        case .organizationNameInput: return 1602
        case .organizationDescriptionInput: return 1603
        case .organizationVerificationNotice: return 1604
        case .starRatingHeader: return 1700
        case .starRatingToggle: return 1701
        case .starRatingPointsInput: return 1702
        case .starRatingNotice: return 1703
        case .profileDataHeader: return 2000
        case .fakeMainUsernameInput: return 2001
        case .fakePhoneToggle: return 2002
        case .fakePhoneInput: return 2003
        case .fakePhonePriceInput: return 2004
        case .fakePurchaseDateInput: return 2005
        case .profileDataNotice: return 2006
        case .nftUsernamesHeader: return 3000
        case .addUsernameAction: return 3001
        case let .nftUsernameItem(index, _, _): return 3100 + Int32(index)
        case .nftUsernamesNotice: return 3999
        case .giftsHeader: return 4000
        case .addNftGiftAction: return 4001
        case .giftConstructorAction: return 4002
        case let .giftItem(index, _, _, _): return 4100 + Int32(index)
        case .giftsNotice: return 4999
        }
    }

    static func ==(lhs: FakeProfileEntry, rhs: FakeProfileEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.premiumHeader(t1), .premiumHeader(t2)),
             let (.premiumNotice(t1), .premiumNotice(t2)),
             let (.publicBalanceHeader(t1), .publicBalanceHeader(t2)),
             let (.publicBalanceNotice(t1), .publicBalanceNotice(t2)),
             let (.organizationVerificationHeader(t1), .organizationVerificationHeader(t2)),
             let (.organizationVerificationNotice(t1), .organizationVerificationNotice(t2)),
             let (.starRatingHeader(t1), .starRatingHeader(t2)),
             let (.starRatingNotice(t1), .starRatingNotice(t2)),
             let (.profileDataHeader(t1), .profileDataHeader(t2)),
             let (.profileDataNotice(t1), .profileDataNotice(t2)),
             let (.nftUsernamesHeader(t1), .nftUsernamesHeader(t2)),
             let (.addUsernameAction(t1), .addUsernameAction(t2)),
             let (.nftUsernamesNotice(t1), .nftUsernamesNotice(t2)),
             let (.giftsHeader(t1), .giftsHeader(t2)),
             let (.addNftGiftAction(t1), .addNftGiftAction(t2)),
             let (.giftConstructorAction(t1), .giftConstructorAction(t2)),
             let (.giftsNotice(t1), .giftsNotice(t2)):
            return t1 == t2
        case let (.visualPremiumToggle(v1), .visualPremiumToggle(v2)),
             let (.publicBalanceToggle(v1), .publicBalanceToggle(v2)),
             let (.organizationVerificationToggle(v1), .organizationVerificationToggle(v2)),
             let (.starRatingToggle(v1), .starRatingToggle(v2)),
             let (.fakePhoneToggle(v1), .fakePhoneToggle(v2)):
            return v1 == v2
        case let (.starsBalanceInput(t1, v1), .starsBalanceInput(t2, v2)),
             let (.tonBalanceInput(t1, v1), .tonBalanceInput(t2, v2)),
             let (.publicBalanceCurrencyInput(t1, v1), .publicBalanceCurrencyInput(t2, v2)),
             let (.publicBalanceAmountInput(t1, v1), .publicBalanceAmountInput(t2, v2)),
             let (.publicWalletAddressInput(t1, v1), .publicWalletAddressInput(t2, v2)),
             let (.organizationNameInput(t1, v1), .organizationNameInput(t2, v2)),
             let (.organizationDescriptionInput(t1, v1), .organizationDescriptionInput(t2, v2)),
             let (.starRatingPointsInput(t1, v1), .starRatingPointsInput(t2, v2)),
             let (.fakeMainUsernameInput(t1, v1), .fakeMainUsernameInput(t2, v2)),
             let (.fakePhoneInput(t1, v1), .fakePhoneInput(t2, v2)),
             let (.fakePhonePriceInput(t1, v1), .fakePhonePriceInput(t2, v2)),
             let (.fakePurchaseDateInput(t1, v1), .fakePurchaseDateInput(t2, v2)):
            return t1 == t2 && v1 == v2
        case let (.nftUsernameItem(i1, u1, p1), .nftUsernameItem(i2, u2, p2)):
            return i1 == i2 && u1 == u2 && p1 == p2
        case let (.giftItem(i1, id1, t1, s1), .giftItem(i2, id2, t2, s2)):
            return i1 == i2 && id1 == id2 && t1 == t2 && s1 == s2
        default:
            return false
        }
    }

    static func <(lhs: FakeProfileEntry, rhs: FakeProfileEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    private func input(presentationData: ItemListPresentationData, title: String, value: String, placeholder: String, capitalization: Bool = false, number: Bool = false, updated: @escaping (String) -> Void) -> ListViewItem {
        return ItemListSingleLineInputItem(
            presentationData: presentationData,
            title: NSAttributedString(string: title, textColor: presentationData.theme.list.itemPrimaryTextColor),
            text: value,
            placeholder: placeholder,
            type: number ? .number : .regular(capitalization: capitalization, autocorrection: false),
            sectionId: self.section,
            textUpdated: updated,
            action: {}
        )
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FakeProfileSettingsArguments
        switch self {
        case let .premiumHeader(text), let .publicBalanceHeader(text), let .organizationVerificationHeader(text), let .starRatingHeader(text), let .profileDataHeader(text), let .nftUsernamesHeader(text), let .giftsHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .visualPremiumToggle(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Визуальный Telegram Premium", value: value, sectionId: self.section, style: .blocks, updated: args.updateVisualPremium)
        case let .starsBalanceInput(title, value):
            return self.input(presentationData: presentationData, title: title, value: value, placeholder: "Например, 5000", number: true, updated: { text in
                let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
                args.updateStarsBalance(clean.isEmpty ? nil : Int64(clean))
            })
        case let .tonBalanceInput(title, value):
            return self.input(presentationData: presentationData, title: title, value: value, placeholder: "Например, 150.5", updated: { text in
                let clean = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
                args.updateTonBalance(clean.isEmpty ? nil : Double(clean))
            })
        case let .premiumNotice(text), let .publicBalanceNotice(text), let .organizationVerificationNotice(text), let .starRatingNotice(text), let .profileDataNotice(text), let .nftUsernamesNotice(text), let .giftsNotice(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section, style: .blocks)
        case let .publicBalanceToggle(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Публичный баланс в профиле", value: value, sectionId: self.section, style: .blocks, updated: args.updatePublicBalanceEnabled)
        case let .publicBalanceCurrencyInput(title, value):
            return self.input(presentationData: presentationData, title: title, value: value, placeholder: "TON или GRAM", capitalization: true, updated: { text in
                let clean = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                args.updatePublicBalanceCurrency(clean.isEmpty ? "TON" : clean)
            })
        case let .publicBalanceAmountInput(title, value):
            return self.input(presentationData: presentationData, title: title, value: value, placeholder: "Например, 1000", updated: { text in
                let clean = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
                args.updatePublicBalanceAmount(clean.isEmpty ? nil : Double(clean))
            })
        case let .publicWalletAddressInput(title, value):
            return self.input(presentationData: presentationData, title: title, value: value, placeholder: "UQDx...", updated: { text in
                args.updatePublicWalletAddress(text.trimmingCharacters(in: .whitespacesAndNewlines))
            })
        case let .organizationVerificationToggle(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Верификация от организации", value: value, sectionId: self.section, style: .blocks, updated: args.updateOrganizationVerificationEnabled)
        case let .organizationNameInput(title, value):
            return self.input(presentationData: presentationData, title: title, value: value, placeholder: "Telegram", capitalization: true, updated: { text in
                let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
                args.updateOrganizationName(clean.isEmpty ? "Telegram" : clean)
            })
        case let .organizationDescriptionInput(title, value):
            return self.input(presentationData: presentationData, title: title, value: value, placeholder: "Официально подтверждено...", updated: { text in
                args.updateOrganizationDescription(text.trimmingCharacters(in: .whitespacesAndNewlines))
            })
        case let .starRatingToggle(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Официальный бейдж рейтинга", value: value, sectionId: self.section, style: .blocks, updated: args.updateRatingEnabled)
        case let .starRatingPointsInput(title, value):
            return self.input(presentationData: presentationData, title: title, value: value, placeholder: "5000", number: true, updated: { text in
                let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
                args.updateRatingPoints(clean.isEmpty ? nil : Int64(clean))
            })
        case let .fakeMainUsernameInput(title, value):
            return self.input(presentationData: presentationData, title: title, value: value, placeholder: "Например, crow", updated: { text in
                let clean = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "@", with: "")
                args.updateMainUsername(clean.isEmpty ? nil : clean)
            })
        case let .fakePhoneToggle(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Анонимный номер", value: value, sectionId: self.section, style: .blocks, updated: args.updateFakePhoneEnabled)
        case let .fakePhoneInput(title, value):
            return self.input(presentationData: presentationData, title: title, value: value, placeholder: "+888 0000 0000", updated: { text in
                args.updateFakePhone(text.trimmingCharacters(in: .whitespacesAndNewlines))
            })
        case let .fakePhonePriceInput(title, value):
            return self.input(presentationData: presentationData, title: title, value: value, placeholder: "150", updated: { text in
                let clean = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
                args.updateFakePhonePriceTon(Double(clean) ?? 150.0)
            })
        case let .fakePurchaseDateInput(title, value):
            return self.input(presentationData: presentationData, title: title, value: value, placeholder: "Например, 15.05.2024", updated: { text in
                let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
                args.updatePurchaseDate(clean.isEmpty ? nil : clean)
            })
        case let .addUsernameAction(text):
            return ItemListActionItem(presentationData: presentationData, title: text, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: args.addUsername)
        case let .nftUsernameItem(_, username, priceTon):
            return WebBrowserDomainExceptionItem(
                presentationData: presentationData,
                systemStyle: .legacy,
                context: args.context,
                title: "@\(username)",
                label: String(format: "%.1f TON", priceTon),
                favicon: nil,
                sectionId: self.section,
                style: .blocks,
                deleted: { args.deleteUsername(username) }
            )
        case let .addNftGiftAction(text):
            return ItemListActionItem(presentationData: presentationData, title: text, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: args.addNftGiftByLink)
        case let .giftConstructorAction(text):
            return ItemListActionItem(presentationData: presentationData, title: text, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: args.openGiftConstructor)
        case let .giftItem(_, id, title, subtitle):
            return WebBrowserDomainExceptionItem(
                presentationData: presentationData,
                systemStyle: .legacy,
                context: args.context,
                title: title,
                label: subtitle,
                favicon: nil,
                sectionId: self.section,
                style: .blocks,
                deleted: { args.deleteGift(id) }
            )
        }
    }
}

public func fakeProfileSettingsController(context: AccountContext) -> ViewController {
    let currentPeerId = context.account.peerId.id._internalGetInt64Value()
    FakeProfileManager.shared.currentAccountPeerId = currentPeerId

    let actionsDisposable = DisposableSet()
    let statePromise = ValuePromise<Int>(0, ignoreRepeated: false)
    let stateValue = Atomic<Int>(value: 0)
    let updateState: () -> Void = {
        let _ = stateValue.modify { $0 + 1 }
        statePromise.set(stateValue.with { $0 })
    }

    let arguments = FakeProfileSettingsArguments(
        context: context,
        updateVisualPremium: { value in
            FakeProfileManager.shared.setVisualPremium(value, for: currentPeerId)
            updateState()
        },
        updateStarsBalance: { balance in
            FakeProfileManager.shared.setFakeStarsBalance(balance, for: currentPeerId)
            updateState()
        },
        updateTonBalance: { balance in
            FakeProfileManager.shared.setFakeTonBalance(balance, for: currentPeerId)
            updateState()
        },
        updateMainUsername: { username in
            FakeProfileManager.shared.setFakeMainUsername(username, for: currentPeerId)
        },
        updateFakePhoneEnabled: { value in
            FakeProfileManager.shared.setFakePhoneEnabled(value, for: currentPeerId)
            updateState()
        },
        updateFakePhone: { phone in
            FakeProfileManager.shared.setFakePhone(phone, for: currentPeerId)
        },
        updateFakePhonePriceTon: { price in
            FakeProfileManager.shared.setFakePhonePriceTon(price, for: currentPeerId)
        },
        updatePurchaseDate: { date in
            FakeProfileManager.shared.setFakePurchaseDateString(date, for: currentPeerId)
        },
        updatePublicBalanceEnabled: { value in
            FakeProfileManager.shared.setPublicBalanceEnabled(value, for: currentPeerId)
            updateState()
        },
        updatePublicBalanceAmount: { value in
            FakeProfileManager.shared.setPublicBalanceAmount(value, for: currentPeerId)
            updateState()
        },
        updatePublicBalanceCurrency: { value in
            FakeProfileManager.shared.setPublicBalanceCurrency(value, for: currentPeerId)
            updateState()
        },
        updatePublicWalletAddress: { value in
            FakeProfileManager.shared.setPublicWalletAddress(value, for: currentPeerId)
            updateState()
        },
        updateOrganizationVerificationEnabled: { value in
            FakeProfileManager.shared.setOrganizationVerificationEnabled(value, for: currentPeerId)
            updateState()
        },
        updateOrganizationName: { value in
            FakeProfileManager.shared.setOrganizationName(value, for: currentPeerId)
            updateState()
        },
        updateOrganizationDescription: { value in
            FakeProfileManager.shared.setOrganizationDescription(value, for: currentPeerId)
            updateState()
        },
        updateRatingEnabled: { value in
            FakeProfileManager.shared.setRatingEnabled(value, for: currentPeerId)
            updateState()
        },
        updateRatingPoints: { value in
            FakeProfileManager.shared.setRatingPoints(value, for: currentPeerId)
            updateState()
        },
        addUsername: {
            let alert = UIAlertController(title: "Добавить NFT-юзернейм", message: "Введите имя пользователя и цену покупки на Fragment в TON", preferredStyle: .alert)
            alert.addTextField { field in
                field.placeholder = "Юзернейм (например, crow)"
                field.autocapitalizationType = .none
                field.autocorrectionType = .no
            }
            alert.addTextField { field in
                field.placeholder = "Цена в TON (например, 250)"
                field.keyboardType = .decimalPad
            }
            alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            alert.addAction(UIAlertAction(title: "Добавить", style: .default, handler: { [weak alert] _ in
                guard let fields = alert?.textFields, fields.count >= 2 else { return }
                let username = (fields[0].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "@", with: "")
                let priceText = (fields[1].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
                guard !username.isEmpty else { return }
                let item = FakeNftUsername(username: username, priceTon: Double(priceText) ?? 0.0, purchaseDate: FakeProfileManager.shared.fakePurchaseDateTimestamp(for: currentPeerId))
                FakeProfileManager.shared.addUsername(item, for: currentPeerId)
                updateState()
            }))
            context.sharedContext.mainWindow?.presentNative(alert)
        },
        deleteUsername: { username in
            FakeProfileManager.shared.removeUsername(named: username, for: currentPeerId)
            updateState()
        },
        addNftGiftByLink: {
            let alert = UIAlertController(title: "Добавить NFT-подарок", message: "Введите ссылку на подарок (например, https://t.me/nft/jelly-bunny-123) или его slug:", preferredStyle: .alert)
            alert.addTextField { field in
                field.placeholder = "https://t.me/nft/slug"
                field.autocapitalizationType = .none
                field.autocorrectionType = .no
            }
            alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            alert.addAction(UIAlertAction(title: "Добавить", style: .default, handler: { [weak alert] _ in
                guard let fields = alert?.textFields, let text = fields.first?.text else { return }
                let rawSlug = parseGiftSlug(from: text)
                guard !rawSlug.isEmpty else { return }
                let (fallbackTitle, fallbackNum) = parseSlugTitleAndNumber(slug: rawSlug)

                let saveGiftWithCraft: (StarGift.UniqueGift, Bool) -> Void = { uniqueGift, canCraft in
                    var innerColor: Int32?
                    var outerColor: Int32?
                    var patternColor: Int32?
                    var textColor: Int32?
                    for attr in uniqueGift.attributes {
                        switch attr {
                        case let .backdrop(_, _, inner, outer, pattern, text, _):
                            innerColor = inner
                            outerColor = outer
                            patternColor = pattern
                            textColor = text
                        case let .model(_, file, _, _):
                            StarGiftsRealMediaCache.shared.register(file: file, for: uniqueGift.giftId)
                        case let .pattern(_, file, _):
                            StarGiftsRealMediaCache.shared.register(file: file, for: uniqueGift.giftId)
                        default:
                            break
                        }
                    }
                    let cleanAttributes = uniqueGift.attributes.filter { $0.attributeType != .originalInfo }
                    let cleanGift = uniqueGift
                        .withAttributes(cleanAttributes)
                        .withOwner(.peerId(EnginePeer.Id(currentPeerId)))
                        .withResellAmounts(nil)
                        .withResellForTonOnly(false)
                    let item = FakeStarGiftItem(
                        baseGiftId: uniqueGift.giftId,
                        patternName: uniqueGift.title,
                        giftNumber: uniqueGift.number,
                        ownerPeerId: currentPeerId,
                        resellPriceStars: 500,
                        resellPriceTon: 10.0,
                        sendDate: Int32(Date().timeIntervalSince1970),
                        canCraft: canCraft,
                        canUpgrade: false,
                        title: uniqueGift.title,
                        slug: uniqueGift.slug,
                        innerColor: innerColor,
                        outerColor: outerColor,
                        patternColor: patternColor,
                        textColor: textColor,
                        rawUniqueGiftData: cleanGift.serialize(),
                        hideOriginalDetails: true
                    )
                    FakeProfileManager.shared.addGift(item, for: currentPeerId)
                    updateState()
                }

                actionsDisposable.add((context.engine.payments.getUniqueStarGift(slug: rawSlug)
                |> deliverOnMainQueue).start(next: { uniqueGift in
                    let isAlreadyCrafted = uniqueGift.attributes.contains(where: {
                        if case let .model(_, _, _, crafted) = $0 { return crafted }
                        return false
                    })
                    let hasCraftChance = (uniqueGift.craftChancePermille ?? 0) > 0
                    if isAlreadyCrafted {
                        saveGiftWithCraft(uniqueGift, false)
                    } else {
                        actionsDisposable.add(((context.engine.payments.getStarGiftUpgradeAttributes(giftId: uniqueGift.giftId)
                        |> take(1)
                        |> timeout(2.0, queue: Queue.mainQueue(), alternate: .single(nil)))
                        |> deliverOnMainQueue).start(next: { upgradeAttributes in
                            let hasCraftedModelInPool = (upgradeAttributes ?? []).contains(where: {
                                if case let .model(_, _, _, crafted) = $0 { return crafted }
                                return false
                            })
                            saveGiftWithCraft(uniqueGift, hasCraftChance || hasCraftedModelInPool)
                        }))
                    }
                }, error: { _ in
                    let lowerTitle = fallbackTitle.lowercased()
                    let fallbackCanCraft = lowerTitle.contains("cap") || lowerTitle.contains("pepe") || lowerTitle.contains("ring") || rawSlug.contains("cap") || rawSlug.contains("pepe")
                    let item = FakeStarGiftItem(
                        patternName: fallbackTitle,
                        giftNumber: fallbackNum,
                        ownerPeerId: currentPeerId,
                        resellPriceStars: 500,
                        resellPriceTon: 10.0,
                        sendDate: Int32(Date().timeIntervalSince1970),
                        canCraft: fallbackCanCraft,
                        canUpgrade: false,
                        title: fallbackTitle,
                        slug: rawSlug,
                        hideOriginalDetails: true
                    )
                    FakeProfileManager.shared.addGift(item, for: currentPeerId)
                    updateState()
                }))
            }))
            context.sharedContext.mainWindow?.presentNative(alert)
        },
        deleteGift: { id in
            FakeProfileManager.shared.removeGift(id: id, for: currentPeerId)
            updateState()
        },
        openGiftConstructor: {
            let controller = fakeGiftConstructorController(context: context, completion: {
                updateState()
            })
            context.sharedContext.mainWindow?.presentNative(controller)
        }
    )

    let signal: Signal<(ItemListControllerState, (ItemListNodeState, Any)), NoError> = combineLatest(
        context.sharedContext.presentationData,
        statePromise.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [FakeProfileEntry] = []
        let manager = FakeProfileManager.shared

        entries.append(.premiumHeader("TELEGRAM PREMIUM, ЗВЕЗДЫ И TON"))
        entries.append(.visualPremiumToggle(manager.isVisualPremium(for: currentPeerId)))
        entries.append(.starsBalanceInput("Баланс Звезд", manager.fakeStarsBalance(for: currentPeerId).flatMap { "\($0)" } ?? ""))
        let tonText = manager.fakeTonBalance(for: currentPeerId).flatMap { value -> String in
            return value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int64(value))" : "\(value)"
        } ?? ""
        entries.append(.tonBalanceInput("Баланс TON", tonText))
        entries.append(.premiumNotice("Визуально активирует статус Premium и заменяет баланс Звезд и TON во всех экранах приложения."))

        entries.append(.publicBalanceHeader("ПУБЛИЧНЫЙ БАЛАНС TON / GRAM И 3D-КАРТА"))
        entries.append(.publicBalanceToggle(manager.isPublicBalanceEnabled(for: currentPeerId)))
        entries.append(.publicBalanceCurrencyInput("Валюта", manager.publicBalanceCurrency(for: currentPeerId)))
        let publicBalance = manager.publicBalanceAmount(for: currentPeerId)
        let publicBalanceText = publicBalance.flatMap { value -> String in
            return value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int64(value))" : "\(value)"
        } ?? ""
        entries.append(.publicBalanceAmountInput("Сумма баланса", publicBalanceText))
        entries.append(.publicWalletAddressInput("Адрес кошелька", manager.publicWalletAddress(for: currentPeerId)))
        entries.append(.publicBalanceNotice("Отображает блок баланса в профиле. По нажатию открывается интерактивная 3D-карта с наклоном пальцем, переворотом на 180° и QR-кодом адреса."))

        entries.append(.organizationVerificationHeader("ВЕРИФИКАЦИЯ ОТ ОРГАНИЗАЦИИ"))
        entries.append(.organizationVerificationToggle(manager.isOrganizationVerificationEnabled(for: currentPeerId)))
        entries.append(.organizationNameInput("Организация", manager.organizationName(for: currentPeerId)))
        entries.append(.organizationDescriptionInput("Описание", manager.organizationDescription(for: currentPeerId)))
        entries.append(.organizationVerificationNotice("Отображает синюю галочку верификации рядом с именем и плашку в профиле. При нажатии открывается подтверждение от организации."))

        entries.append(.starRatingHeader("ОФИЦИАЛЬНЫЙ РЕЙТИНГ В ПРОФИЛЕ"))
        entries.append(.starRatingToggle(manager.isRatingEnabled(for: currentPeerId)))
        let ratingPoints = manager.ratingPoints(for: currentPeerId)
        entries.append(.starRatingPointsInput("Очки рейтинга", ratingPoints.flatMap { "\($0)" } ?? ""))
        let levelDescription: String
        if let ratingPoints {
            levelDescription = "Текущий уровень: \(manager.starRatingLevel(for: ratingPoints)) (очков: \(ratingPoints)). Прогресс до следующего уровня рассчитывается локально."
        } else {
            levelDescription = "Введите количество очков (например, 5000 для уровня 2). Уровень и прогресс рассчитываются локально."
        }
        entries.append(.starRatingNotice(levelDescription))

        entries.append(.profileDataHeader("ДАННЫЕ ПРОФИЛЯ (НОМЕР, ЮЗЕРНЕЙМ, FRAGMENT)"))
        entries.append(.fakeMainUsernameInput("Основной юзернейм", manager.fakeMainUsername(for: currentPeerId) ?? ""))
        entries.append(.fakePhoneToggle(manager.isFakePhoneEnabled(for: currentPeerId)))
        entries.append(.fakePhoneInput("Номер телефона", manager.fakePhone(for: currentPeerId)))
        let phonePrice = manager.fakePhonePriceTon(for: currentPeerId)
        entries.append(.fakePhonePriceInput("Цена номера (TON)", phonePrice.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int64(phonePrice))" : "\(phonePrice)"))
        entries.append(.fakePurchaseDateInput("Дата покупки Fragment", manager.fakePurchaseDateString(for: currentPeerId) ?? ""))
        entries.append(.profileDataNotice("Подменённый номер и основной юзернейм отображаются в профиле и при редактировании. По нажатию открывается шторка Fragment с ценой и датой покупки."))

        entries.append(.nftUsernamesHeader("NFT-ЮЗЕРНЕЙМЫ"))
        entries.append(.addUsernameAction("Добавить юзернейм"))
        for (index, username) in manager.fakeUsernames(for: currentPeerId).enumerated() {
            entries.append(.nftUsernameItem(index: index, username: username.username, priceTon: username.priceTon))
        }
        entries.append(.nftUsernamesNotice("Юзернеймы отображаются в профиле как коллекционные с поддержкой шторки Fragment. Свайп влево для удаления."))

        entries.append(.giftsHeader("ПОДАРКИ В ПРОФИЛЕ"))
        entries.append(.addNftGiftAction("Добавить NFT-подарок по ссылке"))
        entries.append(.giftConstructorAction("Открыть конструктор подарка"))
        for (index, gift) in manager.fakeGifts(for: currentPeerId).enumerated() {
            let title = "#\(gift.giftNumber) • \(gift.title ?? gift.patternName)"
            let subtitle = gift.isUpgraded ? "NFT (Улучшенный)" : "Обычный (Неулучшенный)"
            entries.append(.giftItem(index: index, id: gift.id, title: title, subtitle: subtitle))
        }
        entries.append(.giftsNotice("Подарки отображаются во вкладке «Подарки» профиля с действиями: передать, носить, закрепить, продать или улучшить. Свайп влево для удаления."))

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Оформление профиля"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks
        )
        return (controllerState, (listState, arguments))
    } |> afterDisposed {
        actionsDisposable.dispose()
    }

    return ItemListController(context: context, state: signal)
}
