// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Shared
import Storage
import WebKit
import Common

struct TopTabsUX {
    static let TopTabsViewHeight: CGFloat = 44
    static let TopTabsBackgroundShadowWidth: CGFloat = 12
    static let MinTabWidth: CGFloat = 76
    static let MaxTabWidth: CGFloat = 220
    static let FaderPading: CGFloat = 8
    static let SeparatorWidth: CGFloat = 1
    static let AnimationSpeed: TimeInterval = 0.1
    static let SeparatorYOffset: CGFloat = 7
    static let SeparatorHeight: CGFloat = 32
    static let TabCornerRadius: CGFloat = 8
}

protocol TopTabsDelegate: AnyObject {
    func topTabsDidPressTabs()
    func topTabsDidPressNewTab(_ isPrivate: Bool)
    func topTabsDidChangeTab()
}

class TopTabsViewController: UIViewController, Themeable {
    // MARK: - Properties
    let tabManager: TabManager
    weak var delegate: TopTabsDelegate?
    private var topTabDisplayManager: TabDisplayManager!
    var tabCellIdentifier: TabDisplayer.TabCellIdentifier = TopTabCell.cellIdentifier
    var profile: Profile
    var themeManager: ThemeManager
    var themeObserver: NSObjectProtocol?
    var notificationCenter: NotificationProtocol

    // MARK: - UI Elements
    lazy var collectionView: UICollectionView = {
        let collectionView = UICollectionView(frame: CGRect.zero, collectionViewLayout: TopTabsViewLayout())
        collectionView.register(cellType: TopTabCell.self)
        collectionView.register(cellType: InactiveTabCell.self)
        collectionView.showsVerticalScrollIndicator = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.bounces = false
        collectionView.clipsToBounds = true
        collectionView.accessibilityIdentifier = AccessibilityIdentifiers.Browser.TopTabs.collectionView
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        return collectionView
    }()

    private lazy var tabsButton: TabsButton = .build { button in
        button.semanticContentAttribute = .forceLeftToRight
        button.addTarget(self, action: #selector(TopTabsViewController.tabsTrayTapped), for: .touchUpInside)
        button.accessibilityIdentifier = AccessibilityIdentifiers.Browser.TopTabs.tabsButton
        button.inTopTabs = true
    }

    private lazy var newTab: UIButton = .build { button in
        button.setImage(UIImage.templateImageNamed(ImageIdentifiers.newTab), for: .normal)
        button.semanticContentAttribute = .forceLeftToRight
        button.addTarget(self, action: #selector(TopTabsViewController.newTabTapped), for: .touchUpInside)
        button.accessibilityIdentifier = AccessibilityIdentifiers.Browser.TopTabs.newTabButton
    }

    lazy var privateModeButton: PrivateModeButton = {
        let privateModeButton = PrivateModeButton()
        privateModeButton.semanticContentAttribute = .forceLeftToRight
        privateModeButton.accessibilityIdentifier = AccessibilityIdentifiers.Browser.TopTabs.privateModeButton
        privateModeButton.addTarget(self, action: #selector(TopTabsViewController.togglePrivateModeTapped), for: .touchUpInside)
        privateModeButton.translatesAutoresizingMaskIntoConstraints = false
        return privateModeButton
    }()

    private lazy var tabLayoutDelegate: TopTabsLayoutDelegate = {
        let delegate = TopTabsLayoutDelegate()
        delegate.scrollViewDelegate = self
        delegate.tabSelectionDelegate = topTabDisplayManager
        return delegate
    }()

    private lazy var topTabFader: TopTabFader = {
        let fader = TopTabFader()
        fader.semanticContentAttribute = .forceLeftToRight
        fader.translatesAutoresizingMaskIntoConstraints = false

        return fader
    }()

    // MARK: - Inits
    init(tabManager: TabManager,
         profile: Profile,
         themeManager: ThemeManager = AppContainer.shared.resolve(),
         notificationCenter: NotificationProtocol = NotificationCenter.default) {
        self.tabManager = tabManager
        self.profile = profile
        self.themeManager = themeManager
        self.notificationCenter = notificationCenter
        super.init(nibName: nil, bundle: nil)

        topTabDisplayManager = TabDisplayManager(collectionView: self.collectionView,
                                                 tabManager: self.tabManager,
                                                 tabDisplayer: self,
                                                 reuseID: TopTabCell.cellIdentifier,
                                                 tabDisplayType: .TopTabTray,
                                                 profile: profile,
                                                 theme: themeManager.currentTheme)
        self.tabManager.tabDisplayType = .TopTabTray
        collectionView.dataSource = topTabDisplayManager
        collectionView.delegate = tabLayoutDelegate
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        view.setNeedsLayout()
        view.layoutIfNeeded()
        topTabDisplayManager.tabDisplayType = .TopTabTray
        refreshTabs()
    }

    func refreshTabs() {
        topTabDisplayManager.refreshStore(evenIfHidden: true)
    }

    deinit {
        tabManager.removeDelegate(self.topTabDisplayManager)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        collectionView.dragDelegate = topTabDisplayManager
        collectionView.dropDelegate = topTabDisplayManager

        listenForThemeChange(view)
        setupLayout()

        // Setup UIDropInteraction to handle dragging and dropping
        // links onto the "New Tab" button.
        let dropInteraction = UIDropInteraction(delegate: topTabDisplayManager)
        newTab.addInteraction(dropInteraction)

        tabsButton.applyTheme()
        applyUIMode(isPrivate: tabManager.selectedTab?.isPrivate ?? false)

        updateTabCount(topTabDisplayManager.dataStore.count, animated: false)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        UserDefaults.standard.set(tabManager.selectedTab?.isPrivate ?? false,
                                  forKey: PrefsKeys.LastSessionWasPrivate)
    }

    func switchForegroundStatus(isInForeground reveal: Bool) {
        // Called when the app leaves the foreground to make sure no information is inadvertently revealed
        if let cells = self.collectionView.visibleCells as? [TopTabCell] {
            let alpha: CGFloat = reveal ? 1 : 0
            for cell in cells {
                cell.titleText.alpha = alpha
                cell.favicon.alpha = alpha
            }
        }
    }

    func updateTabCount(_ count: Int, animated: Bool = true) {
        self.tabsButton.updateTabCount(count, animated: animated)
    }

    @objc
    func tabsTrayTapped() {
        self.topTabDisplayManager.refreshStore(evenIfHidden: true)
        delegate?.topTabsDidPressTabs()
    }

    @objc
    func newTabTapped() {
        self.delegate?.topTabsDidPressNewTab(self.topTabDisplayManager.isPrivate)
    }

    @objc
    func togglePrivateModeTapped() {
        topTabDisplayManager.togglePrivateMode(isOn: !topTabDisplayManager.isPrivate,
                                               createTabOnEmptyPrivateMode: true,
                                               shouldSelectMostRecentTab: true)
        self.privateModeButton.setSelected(topTabDisplayManager.isPrivate, animated: true)
    }

    func scrollToCurrentTab(_ animated: Bool = true, centerCell: Bool = false) {
        guard let currentTab = tabManager.selectedTab,
              let index = topTabDisplayManager.dataStore.index(of: currentTab),
              !collectionView.frame.isEmpty
        else { return }

        ensureMainThread { [self] in
            if let frame = collectionView.layoutAttributesForItem(at: IndexPath(row: index, section: 0))?.frame {
                if centerCell {
                    collectionView.scrollToItem(at: IndexPath(item: index, section: 0), at: .centeredHorizontally, animated: false)
                } else {
                    // Padding is added to ensure the tab is completely visible (none of the tab is under the fader)
                    let padFrame = frame.insetBy(dx: -(TopTabsUX.TopTabsBackgroundShadowWidth+TopTabsUX.FaderPading), dy: 0)
                    if animated {
                        UIView.animate(withDuration: TopTabsUX.AnimationSpeed, animations: {
                            self.collectionView.scrollRectToVisible(padFrame, animated: true)
                        })
                    } else {
                        collectionView.scrollRectToVisible(padFrame, animated: false)
                    }
                }
            }
        }
    }

    private func setupLayout() {
        view.addSubview(topTabFader)
        topTabFader.addSubview(collectionView)
        view.addSubview(tabsButton)
        view.addSubview(newTab)
        view.addSubview(privateModeButton)

        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: TopTabsUX.TopTabsViewHeight),

            newTab.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            newTab.trailingAnchor.constraint(equalTo: tabsButton.leadingAnchor),
            newTab.widthAnchor.constraint(equalTo: view.heightAnchor),
            newTab.heightAnchor.constraint(equalTo: view.heightAnchor),

            tabsButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            tabsButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            tabsButton.widthAnchor.constraint(equalTo: view.heightAnchor),
            tabsButton.heightAnchor.constraint(equalTo: view.heightAnchor),

            privateModeButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            privateModeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            privateModeButton.widthAnchor.constraint(equalTo: view.heightAnchor),
            privateModeButton.heightAnchor.constraint(equalTo: view.heightAnchor),

            topTabFader.topAnchor.constraint(equalTo: view.topAnchor),
            topTabFader.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            topTabFader.leadingAnchor.constraint(equalTo: privateModeButton.trailingAnchor),
            topTabFader.trailingAnchor.constraint(equalTo: newTab.leadingAnchor),

            collectionView.topAnchor.constraint(equalTo: topTabFader.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: topTabFader.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: topTabFader.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: topTabFader.trailingAnchor),
        ])
    }

    private func handleFadeOutAfterTabSelection() {
        guard let currentTab = tabManager.selectedTab,
              let index = topTabDisplayManager.dataStore.index(of: currentTab),
              !collectionView.frame.isEmpty
        else { return }

        // Check whether first or last tab is being selected.
        if index == 0 {
            topTabFader.setFader(forSides: .right)
        } else if index == topTabDisplayManager.dataStore.count - 1 {
            topTabFader.setFader(forSides: .left)
        } else if collectionView.contentSize.width <= collectionView.frame.size.width { // all tabs are visible
            topTabFader.setFader(forSides: .none)
        }
    }
}

extension TopTabsViewController: TabDisplayer {
    func focusSelectedTab() {
        self.scrollToCurrentTab(true)
        self.handleFadeOutAfterTabSelection()
    }

    func cellFactory(for cell: UICollectionViewCell, using tab: Tab) -> UICollectionViewCell {
        guard let tabCell = cell as? TopTabCell else { return UICollectionViewCell() }
        tabCell.delegate = self
        let isSelected = (tab == tabManager.selectedTab)
        tabCell.configureWith(tab: tab,
                              isSelected: isSelected,
                              theme: themeManager.currentTheme)
        // Not all cells are visible when the appearance changes. Let's make sure
        // the cell has the proper theme when recycled.
        tabCell.applyTheme(theme: themeManager.currentTheme)
        return tabCell
    }
}

extension TopTabsViewController: TopTabCellDelegate {
    func tabCellDidClose(_ cell: UICollectionViewCell) {
        topTabDisplayManager.closeActionPerformed(forCell: cell)
        NotificationCenter.default.post(name: .TopTabsTabClosed, object: nil)
    }
}

extension TopTabsViewController: NotificationThemeable, PrivateModeUI {
    func applyUIMode(isPrivate: Bool) {
        topTabDisplayManager.togglePrivateMode(isOn: isPrivate, createTabOnEmptyPrivateMode: true)

        privateModeButton.applyTheme(theme: themeManager.currentTheme)
        privateModeButton.applyUIMode(isPrivate: topTabDisplayManager.isPrivate)
    }

    func applyTheme() {
        view.backgroundColor = themeManager.currentTheme.colors.layer3
        tabsButton.applyTheme()
        privateModeButton.applyTheme(theme: themeManager.currentTheme)
        newTab.tintColor = themeManager.currentTheme.colors.iconPrimary
        collectionView.backgroundColor = view.backgroundColor
        collectionView.reloadData()
        topTabDisplayManager.refreshStore()
    }
}

// MARK: TopTabsScrollDelegate
extension TopTabsViewController: TopTabsScrollDelegate {
    // disable / enable TopTabFader dynamically based on visible tabs
    func collectionViewDidScroll(_ scrollView: UIScrollView) {
        let offsetX = scrollView.contentOffset.x
        let scrollViewWidth = scrollView.frame.size.width
        let scrollViewContentSize = scrollView.contentSize.width

        let reachedLeftEnd = offsetX == 0
        let reachedRightEnd = (scrollViewContentSize - offsetX) == scrollViewWidth

        if reachedLeftEnd {
            topTabFader.setFader(forSides: .right)
        } else if reachedRightEnd {
            topTabFader.setFader(forSides: .left)
        } else {
            topTabFader.setFader(forSides: .both)
        }
    }
}
