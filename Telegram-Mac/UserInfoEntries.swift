//
//  UserInfoEntries.swift
//  Telegram-Mac
//
//  Created by keepcoder on 12/10/2016.
//  Copyright © 2016 Telegram. All rights reserved.
//

import Cocoa
import TelegramCoreMac
import SwiftSignalKitMac
import PostboxMac
import TGUIKit


struct UserInfoEditingState: Equatable {
    let editingFirstName: String?
    let editingLastName: String?
    
    init(editingFirstName:String? = nil, editingLastName:String? = nil ) {
        self.editingFirstName = editingFirstName
        self.editingLastName = editingLastName
    }
    
    func withUpdatedEditingFirstNameText(_ editingFirstName: String?) -> UserInfoEditingState {
        return UserInfoEditingState(editingFirstName: editingFirstName, editingLastName: self.editingLastName)
    }
    func withUpdatedEditingLastNameText(_ editingLastName: String?) -> UserInfoEditingState {
        return UserInfoEditingState(editingFirstName: self.editingFirstName, editingLastName: editingLastName)
    }
    
    static func ==(lhs: UserInfoEditingState, rhs: UserInfoEditingState) -> Bool {
        if lhs.editingFirstName != rhs.editingFirstName {
            return false
        }
        if lhs.editingLastName != rhs.editingLastName {
            return false
        }
        return true
    }
}



final class UserInfoState : PeerInfoState {
    let editingState: UserInfoEditingState?
    let savingData: Bool
    
    
    init(editingState: UserInfoEditingState?, savingData: Bool) {
        self.editingState = editingState
        self.savingData = savingData
    }
    
    override init() {
        self.editingState = nil
        self.savingData = false
    }
    
    func isEqual(to: PeerInfoState) -> Bool {
        if let to = to as? UserInfoState {
            return self == to
        }
        return false
    }
    
    static func ==(lhs: UserInfoState, rhs: UserInfoState) -> Bool {
        if lhs.editingState != rhs.editingState {
            return false
        }
        if lhs.savingData != rhs.savingData {
            return false
        }
        
        return true
    }
    
    func withUpdatedSavingData(_ savingData: Bool) -> UserInfoState {
        return UserInfoState(editingState: self.editingState, savingData: savingData)
    }
    
    func withUpdatedEditingState(_ editingState: UserInfoEditingState?) -> UserInfoState {
        return UserInfoState(editingState: editingState, savingData: self.savingData)
    }
    
}

class UserInfoArguments : PeerInfoArguments {
    
    
    private let shareDisposable = MetaDisposable()
    private let blockDisposable = MetaDisposable()
    private let startSecretChatDisposable = MetaDisposable()
    private let updatePeerNameDisposable = MetaDisposable()
    private let deletePeerContactDisposable = MetaDisposable()
    
    func shareContact() {
        shareDisposable.set((account.postbox.loadedPeerWithId(peerId) |> deliverOnMainQueue).start(next: { [weak self] peer in
            if let account = self?.account {
                showModal(with: ShareModalController(ShareContactObject(account, user: peer as! TelegramUser)), for: mainWindow)
            }
        }))
    }
    
    func addContact() {
        shareDisposable.set(addContactPeerInteractively(account: account, peerId: peerId).start())
    }
    
    override func updateEditable(_ editable: Bool, peerView: PeerView) {
        
        let account = self.account
        let peerId = self.peerId
        let updateState:((UserInfoState)->UserInfoState)->Void = { [weak self] f in
            self?.updateState(f)
        }
        
        if editable {
            if let peer = peerViewMainPeer(peerView) as? TelegramUser {
                updateState { state -> UserInfoState in
                    return state.withUpdatedEditingState(UserInfoEditingState(editingFirstName: peer.firstName, editingLastName: peer.lastName))
                }
            }
        } else {
            var updateValues: (firstName: String?, lastName: String?) = (nil, nil)
            updateState { state in
                if let peer = peerViewMainPeer(peerView) as? TelegramUser, peer.firstName != state.editingState?.editingFirstName || peer.lastName != state.editingState?.editingLastName  {
                    updateValues.firstName = state.editingState?.editingFirstName
                    updateValues.lastName = state.editingState?.editingLastName
                    return state.withUpdatedSavingData(true)
                } else {
                    return state.withUpdatedEditingState(nil)
                }
            }
            
            let updateNames: Signal<Void, Void>
            
            if let firstName = updateValues.firstName, let lastName = updateValues.lastName {
                updateNames = showModalProgress(signal: updateContactName(account: account, peerId: peerId, firstName: firstName, lastName: lastName) |> mapError {_ in} |> deliverOnMainQueue, for: mainWindow)
            } else {
                updateNames = .complete()
            }
            
            self.updatePeerNameDisposable.set(updateNames.start(error: { _ in
                updateState { state in
                    return state.withUpdatedSavingData(false)
                }
            }, completed: {
                updateState { state in
                    return state.withUpdatedSavingData(false).withUpdatedEditingState(nil)
                }
            }))
            
        }
        
        
    }
    
    
    
    func startSecretChat() {
        
        let signal = account.postbox.modify { [weak self] modifier -> (Peer?, Account?) in
            
            if let peerId = self?.peerId, let peer = modifier.getPeer(peerId), let account = self?.account {
                return (peer, account)
            } else {
                return (nil, nil)
            }
            
            } |> deliverOnMainQueue  |> mapToSignal { peer, account -> Signal<PeerId, Void> in
                if let peer = peer, let account = account {
                    let confirm = confirmSignal(for: mainWindow, header: appName, information: tr(.peerInfoConfirmStartSecretChat(peer.displayTitle)))
                    return confirm |> filter {$0} |> mapToSignal { (_) -> Signal<PeerId, Void> in
                        return showModalProgress(signal: createSecretChat(account: account, peerId: peer.id), for: mainWindow) |> mapError {_ in}
                    }
                } else {
                    return .complete()
                }
            } |> deliverOnMainQueue
        
        
        
        startSecretChatDisposable.set(signal.start(next: { [weak self] peerId in
            if let strongSelf = self {
                strongSelf.pushViewController(ChatController(account: strongSelf.account, peerId: peerId))
            }
        }))
    }
    
    func updateState(_ f: (UserInfoState) -> UserInfoState) -> Void {
        updateInfoState { state -> PeerInfoState in
            return f(state as! UserInfoState)
        }
    }
    
    func updateEditingNames(firstName: String?, lastName:String?) -> Void {
        updateState { state in
            if let editingState = state.editingState {
                return state.withUpdatedEditingState(editingState.withUpdatedEditingFirstNameText(firstName).withUpdatedEditingLastNameText(lastName))
            } else {
                return state
            }
        }
    }
    
    func updateBlocked(_ blocked:Bool) {
        blockDisposable.set(requestUpdatePeerIsBlocked(account: account, peerId: peerId, isBlocked: blocked).start())
    }
    
    func deleteContact() {
        let account = self.account
        let peerId = self.peerId
        deletePeerContactDisposable.set((confirmSignal(for: mainWindow, header: appName, information: tr(.peerInfoConfirmDeleteContact))
            |> filter {$0}
            |> mapToSignal { _ in
                showModalProgress(signal: deleteContactPeerInteractively(account: account, peerId: peerId) |> deliverOnMainQueue, for: mainWindow)
            }).start(completed: { [weak self] in
                self?.pullNavigation()?.back()
            }))
    }
    
    func encryptionKey() {
        pushViewController(SecretChatKeyViewController(account: account, peerId: peerId))
    }
    
    func groupInCommon() -> Void {
        pushViewController(GroupsInCommonViewController(account: account, peerId: peerId))
    }
    
    deinit {
        shareDisposable.dispose()
        blockDisposable.dispose()
        startSecretChatDisposable.dispose()
        updatePeerNameDisposable.dispose()
        deletePeerContactDisposable.dispose()
    }
    
}



enum UserInfoEntry: PeerInfoEntry {
    case info(sectionId:Int, PeerView, editable:Bool)
    case about(sectionId:Int, text: String)
    case bio(sectionId:Int, text: String)
    case phoneNumber(sectionId:Int, index: Int, value: PhoneNumberWithLabel)
    case userName(sectionId:Int, value: String)
    case sendMessage(sectionId:Int)
    case shareContact(sectionId:Int)
    case addContact(sectionId:Int)
    case startSecretChat(sectionId:Int)
    case sharedMedia(sectionId:Int)
    case notifications(sectionId:Int, settings: PeerNotificationSettings?)
    case groupInCommon(sectionId:Int, count:Int)
    case block(sectionId:Int, Bool)
    case deleteChat(sectionId: Int)
    case deleteContact(sectionId: Int)
    case encryptionKey(sectionId: Int)
    case section(sectionId:Int)
    
    var stableId: PeerInfoEntryStableId {
        return IntPeerInfoEntryStableId(value: self.stableIndex)
    }
    
    func isEqual(to: PeerInfoEntry) -> Bool {
        guard let entry = to as? UserInfoEntry else {
            return false
        }
        
        switch self {
        case let .info(lhsSectionId, lhsPeerView, lhsEditable):
            switch entry {
            case let .info(rhsSectionId, rhsPeerView, rhsEditable):
                
                if lhsSectionId != rhsSectionId {
                    return false
                }
                
                if lhsEditable != rhsEditable {
                    return false
                }
                
                let lhsPeer = peerViewMainPeer(lhsPeerView)
                let lhsCachedData = lhsPeerView.cachedData
                
                let rhsPeer = peerViewMainPeer(rhsPeerView)
                let rhsCachedData = rhsPeerView.cachedData
                
                if let lhsPeer = lhsPeer, let rhsPeer = rhsPeer {
                    if !lhsPeer.isEqual(rhsPeer) {
                        return false
                    }
                } else if (lhsPeer == nil) != (rhsPeer != nil) {
                    return false
                }
                
                
                
                if let lhsCachedData = lhsCachedData, let rhsCachedData = rhsCachedData {
                    if !lhsCachedData.isEqual(to: rhsCachedData) {
                        return false
                    }
                } else if (lhsCachedData == nil) != (rhsCachedData == nil) {
                    return false
                }
                return true
            default:
                return false
            }
        case let .about(sectionId, text):
            switch entry {
            case .about(sectionId, text):
                return true
            default:
                return false
            }
        case let .bio(sectionId, text):
            switch entry {
            case .bio(sectionId, text):
                return true
            default:
                return false
            }
        case let .phoneNumber(lhsSectionId, lhsIndex, lhsValue):
            switch entry {
            case let .phoneNumber(rhsSectionId, rhsIndex, rhsValue) where lhsIndex == rhsIndex && lhsValue == rhsValue && lhsSectionId == rhsSectionId:
                return true
            default:
                return false
            }
        case let .userName(sectionId, value):
            switch entry {
            case .userName(sectionId, value):
                return true
            default:
                return false
            }
        case let .sendMessage(sectionId):
            switch entry {
            case .sendMessage(sectionId):
                return true
            default:
                return false
            }
        case let .shareContact(sectionId):
            switch entry {
            case .shareContact(sectionId):
                return true
            default:
                return false
            }
        case let .addContact(sectionId):
            switch entry {
            case .addContact(sectionId):
                return true
            default:
                return false
            }
        case let .startSecretChat(sectionId):
            switch entry {
            case .startSecretChat(sectionId):
                return true
            default:
                return false
            }
        case let .sharedMedia(sectionId):
            switch entry {
            case .sharedMedia(sectionId):
                return true
            default:
                return false
            }
        case let .notifications(lhsSectionId, lhsSettings):
            switch entry {
            case let .notifications(rhsSectionId, rhsSettings):
                if lhsSectionId != rhsSectionId {
                    return false
                }
                if let lhsSettings = lhsSettings, let rhsSettings = rhsSettings {
                    return lhsSettings.isEqual(to: rhsSettings)
                } else if (lhsSettings != nil) != (rhsSettings != nil) {
                    return false
                }
                return true
            default:
                return false
            }
        case let .block(sectionId, isBlocked):
            switch entry {
            case .block(sectionId, isBlocked):
                return true
            default:
                return false
            }
        case let .groupInCommon(sectionId, count):
            switch entry {
            case .groupInCommon(sectionId, count):
                return true
            default:
                return false
            }
        case let .deleteChat(sectionId):
            switch entry {
            case .deleteChat(sectionId):
                return true
            default:
                return false
            }
        case let .deleteContact(sectionId):
            switch entry {
            case .deleteContact(sectionId):
                return true
            default:
                return false
            }
        case let .encryptionKey(sectionId):
            switch entry {
            case .encryptionKey(sectionId):
                return true
            default:
                return false
            }
        case let .section(lhsId):
            switch entry {
            case let .section(rhsId):
                return lhsId == rhsId
            default:
                return false
            }
        }
    }
    
    private var stableIndex: Int {
        switch self {
        case .info:
            return 0
        case .about:
            return 1
        case .phoneNumber:
            return 2
        case .bio:
            return 3
        case .userName:
            return 4
        case .sendMessage:
            return 5
        case .shareContact:
            return 6
        case .addContact:
            return 7
        case .startSecretChat:
            return 8
        case .sharedMedia:
            return 9
        case .notifications:
            return 10
        case .encryptionKey:
            return 11
        case .groupInCommon:
            return 12
        case .block:
            return 13
        case .deleteChat:
            return 14
        case .deleteContact:
            return 15
        case let .section(id):
            return (id + 1) * 1000 - id
        }
    }
    
    private var sortIndex:Int {
        switch self {
        case let .info(sectionId, _, _):
            return (sectionId * 1000) + stableIndex
        case let .about(sectionId, _):
            return (sectionId * 1000) + stableIndex
        case let .bio(sectionId, _):
            return (sectionId * 1000) + stableIndex
        case let .phoneNumber(sectionId, _, _):
            return (sectionId * 1000) + stableIndex
        case let .userName(sectionId, _):
            return (sectionId * 1000) + stableIndex
        case let .sendMessage(sectionId):
            return (sectionId * 1000) + stableIndex
        case let .shareContact(sectionId):
            return (sectionId * 1000) + stableIndex
        case let .addContact(sectionId):
            return (sectionId * 1000) + stableIndex
        case let .startSecretChat(sectionId):
            return (sectionId * 1000) + stableIndex
        case let .sharedMedia(sectionId):
            return (sectionId * 1000) + stableIndex
        case let .groupInCommon(sectionId, _):
            return (sectionId * 1000) + stableIndex
        case let .notifications(sectionId, _):
            return (sectionId * 1000) + stableIndex
        case let .encryptionKey(sectionId):
            return (sectionId * 1000) + stableIndex
        case let .block(sectionId, _):
            return (sectionId * 1000) + stableIndex
        case let .deleteChat(sectionId):
            return (sectionId * 1000) + stableIndex
        case let .deleteContact(sectionId):
            return (sectionId * 1000) + stableIndex
        case let .section(id):
            return (id + 1) * 1000 - id
        }
        
    }
    
    func isOrderedBefore(_ entry: PeerInfoEntry) -> Bool {
        guard let other = entry as? UserInfoEntry else {
            return false
        }
        
        return self.sortIndex > other.sortIndex
    }
    
    
    
    func item( initialSize:NSSize, arguments:PeerInfoArguments) -> TableRowItem {
        
        let arguments = arguments as! UserInfoArguments
        let state = arguments.state as! UserInfoState
        switch self {
        case let .info(_, peerView, editable):
            return PeerInfoHeaderItem(initialSize, stableId:stableId.hashValue, account:arguments.account, peerView:peerView, editable: editable, updatingPhotoState: nil, firstNameEditableText: state.editingState?.editingFirstName, lastNameEditableText: state.editingState?.editingLastName, textChangeHandler: { firstName, lastName in
                arguments.updateEditingNames(firstName: firstName, lastName: lastName)
            })
        case let .about(_, text):
            return  TextAndLabelItem(initialSize, stableId:stableId.hashValue, label:tr(.peerInfoAbout), text:text, account: arguments.account, detectLinks:true)
        case let .bio(_, text):
            return  TextAndLabelItem(initialSize, stableId:stableId.hashValue, label:tr(.peerInfoBio), text:text, account: arguments.account, detectLinks:false)
        case let .phoneNumber(_, _, value):
            return  TextAndLabelItem(initialSize, stableId: stableId.hashValue, label:value.label, text:formatPhoneNumber(value.number), account: arguments.account)
        case let .userName(_, value):
            return  TextAndLabelItem(initialSize, stableId: stableId.hashValue, label:tr(.peerInfoUsername), text:"@\(value)", account: arguments.account)
        case .sendMessage:
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: tr(.peerInfoSendMessage), nameStyle: blueActionButton, type: .none, action: {
                arguments.peerChat(arguments.peerId)
            })
        case .shareContact:
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: tr(.peerInfoShareContact), nameStyle: blueActionButton, type: .none, action: {
                arguments.shareContact()
            })
        case .addContact:
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: tr(.peerInfoAddContact), nameStyle: blueActionButton, type: .none, action: {
                arguments.addContact()
            })
        case .startSecretChat:
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: tr(.peerInfoStartSecretChat), nameStyle: blueActionButton, type: .none, action: {
                arguments.startSecretChat()
            })
        case .sharedMedia:
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: tr(.peerInfoSharedMedia), type: .none, action: {
                arguments.sharedMedia()
            })
        case let .groupInCommon(sectionId: _, count: count):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: tr(.peerInfoGroupsInCommon), type: .context(stateback: { () -> String in
                return "\(count)"
            }), action: {
                arguments.groupInCommon()
            })
            
        case let .notifications(_, settings):
            
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: tr(.peerInfoNotifications), type: .switchable(stateback: { () -> Bool in
                
                if let settings = settings as? TelegramPeerNotificationSettings, case .muted = settings.muteState {
                    return false
                } else {
                    return true
                }
                
            }), action: {
                arguments.toggleNotifications()
            })
        case .encryptionKey:
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: tr(.peerInfoEncryptionKey), type: .none, action: {
                arguments.encryptionKey()
            })
        case let .block(_, isBlocked):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: !isBlocked ? tr(.peerInfoBlockUser) : tr(.peerInfoUnblockUser), nameStyle:redActionButton, type: .none, action: {
                arguments.updateBlocked(!isBlocked)
            })
        case .deleteChat:
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: tr(.peerInfoDeleteSecretChat), nameStyle: redActionButton, type: .none, action: {
                arguments.delete()
            })
        case .deleteContact:
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: tr(.peerInfoDeleteContact), nameStyle: redActionButton, type: .none, action: {
                arguments.deleteContact()
            })
        case .section(_):
            return GeneralRowItem(initialSize, height:20, stableId: stableId.hashValue)
        }
        
    }
    
}



func userInfoEntries(view: PeerView, arguments: PeerInfoArguments) -> [PeerInfoEntry] {
    
    let arguments = arguments as! UserInfoArguments
    let state = arguments.state as! UserInfoState
    
    var entries: [PeerInfoEntry] = []
    
    var sectionId:Int = 1
    
    
    entries.append(UserInfoEntry.info(sectionId: sectionId, view, editable: state.editingState != nil))
    
    if let peer = view.peers[view.peerId] {
        
        if let cachedUserData = view.cachedData as? CachedUserData, state.editingState == nil {
            if let about = cachedUserData.about, !about.isEmpty {
                if peer.isBot {
                    entries.append(UserInfoEntry.about(sectionId: sectionId, text: about))
                } else {
                    entries.append(UserInfoEntry.bio(sectionId: sectionId, text: about))
                }
            }
        }
        if let user = peerViewMainPeer(view) as? TelegramUser {
            
            if state.editingState == nil {
                if let phoneNumber = user.phone, !phoneNumber.isEmpty {
                    entries.append(UserInfoEntry.phoneNumber(sectionId: sectionId, index: 0, value: PhoneNumberWithLabel(label: tr(.peerInfoPhone), number: phoneNumber)))
                }
                if let username = user.username, !username.isEmpty {
                    entries.append(UserInfoEntry.userName(sectionId: sectionId, value: username))
                }
                
                entries.append(UserInfoEntry.section(sectionId: sectionId))
                sectionId += 1
                
                if !(peer is TelegramSecretChat) {
                    entries.append(UserInfoEntry.sendMessage(sectionId: sectionId))
                    if let peer = peer as? TelegramUser, let phone = peer.phone, !phone.isEmpty {
                        if view.peerIsContact {
                            entries.append(UserInfoEntry.shareContact(sectionId: sectionId))
                        } else {
                            entries.append(UserInfoEntry.addContact(sectionId: sectionId))
                        }
                    }
                }
                
                if arguments.account.peerId != arguments.peerId, !(peer is TelegramSecretChat), let peer = peer as? TelegramUser, peer.botInfo == nil {
                    entries.append(UserInfoEntry.startSecretChat(sectionId: sectionId))
                }
                entries.append(UserInfoEntry.section(sectionId: sectionId))
                sectionId += 1
                
                entries.append(UserInfoEntry.sharedMedia(sectionId: sectionId))
            }
            
            entries.append(UserInfoEntry.notifications(sectionId: sectionId, settings: view.notificationSettings))
            
            if (peer is TelegramSecretChat) {
                entries.append(UserInfoEntry.encryptionKey(sectionId: sectionId))
            }
            
            if let cachedData = view.cachedData as? CachedUserData, arguments.account.peerId != arguments.peerId {
                
                if state.editingState == nil {
                    if cachedData.commonGroupCount > 0 {
                        entries.append(UserInfoEntry.groupInCommon(sectionId: sectionId, count: Int(cachedData.commonGroupCount)))
                    }
                    entries.append(UserInfoEntry.section(sectionId: sectionId))
                    sectionId += 1
                    
                    entries.append(UserInfoEntry.block(sectionId: sectionId, cachedData.isBlocked))
                } else {
                    entries.append(UserInfoEntry.section(sectionId: sectionId))
                    sectionId += 1
                    entries.append(UserInfoEntry.deleteContact(sectionId: sectionId))
                }
                
                
            }
            if peer is TelegramSecretChat {
                entries.append(UserInfoEntry.section(sectionId: sectionId))
                sectionId += 1
                
                entries.append(UserInfoEntry.deleteChat(sectionId: sectionId))
            }
        }
    }
    
    return entries.sorted(by: { (p1, p2) -> Bool in
        return p1.isOrderedBefore(p2)
    })
}
