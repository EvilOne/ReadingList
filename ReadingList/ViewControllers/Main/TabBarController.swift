import UIKit
import CoreSpotlight
import Eureka

final class TabBarController: UITabBarController {

    convenience init() {
        self.init(nibName: nil, bundle: nil)
    }

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        initialise()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        initialise()
    }

    enum TabOption: Int {
        case toRead = 0
        case finished = 1
        case organise = 2
        case settings = 3
    }

    func initialise() {
        viewControllers = getRootViewControllers()
        configureTabIcons()
        monitorThemeSetting()
    }

    func getRootViewControllers() -> [UIViewController] {
        // The first two tabs of the tab bar controller are to the same storyboard. We cannot have different tab bar icons
        // if they are set up in storyboards, so we do them in code here, instead.
        let toRead = UIStoryboard.BookTable.instantiateRoot() as! UISplitViewController
        (toRead.masterNavigationRoot as! BookTable).readStates = [.reading, .toRead]

        let finished = UIStoryboard.BookTable.instantiateRoot() as! UISplitViewController
        (finished.masterNavigationRoot as! BookTable).readStates = [.finished]

        return [toRead, finished, UIStoryboard.Organize.instantiateRoot(), UIStoryboard.Settings.instantiateRoot()]
    }

    func configureTabIcons() {
        guard let items = tabBar.items else { preconditionFailure("Missing tab bar items") }
        // Tabs 3 and 4 are usually configured by the Organise and Settings storyboards, but configure them anyway (there is a use
        // case - when restoring from a backup we may have switched out the view controllers temporarily).
        items[0].configure(tag: TabOption.toRead.rawValue, title: "To Read", image: #imageLiteral(resourceName: "courses"), selectedImage: #imageLiteral(resourceName: "courses-filled"))
        items[1].configure(tag: TabOption.finished.rawValue, title: "Finished", image: #imageLiteral(resourceName: "to-do"), selectedImage: #imageLiteral(resourceName: "to-do-filled"))
        items[2].configure(tag: TabOption.organise.rawValue, title: NSLocalizedString("OrganizeTabText", comment: ""), image: #imageLiteral(resourceName: "organise"), selectedImage: #imageLiteral(resourceName: "organise-filled"))
        items[3].configure(tag: TabOption.settings.rawValue, title: "Settings", image: #imageLiteral(resourceName: "settings"), selectedImage: #imageLiteral(resourceName: "settings-filled"))
    }

    var selectedTab: TabOption {
        get { return TabOption(rawValue: selectedIndex)! }
        set { selectedIndex = newValue.rawValue }
    }

    var selectedSplitViewController: UISplitViewController? {
        return selectedViewController as? UISplitViewController
    }

    var selectedBookTable: BookTable? {
        return selectedSplitViewController?.masterNavigationController.viewControllers.first as? BookTable
    }

    func simulateBookSelection(_ book: Book, allowTableObscuring: Bool) {
        selectedTab = book.readState == .finished ? .finished : .toRead
        // Crashes observed on iOS 13: simulateBookSelection crashed as implicitly unwrapped optionals were nil,
        // which could only be the case if viewDidLoad had not been called. Check whether the view is loaded, and
        // if not, schedule the work on the main thread, so that the view can be loaded first. Check again that
        // the view is loaded, to be safe.
        if selectedBookTable?.viewIfLoaded == nil {
            DispatchQueue.main.async { [unowned self] in
                if self.selectedBookTable?.viewIfLoaded != nil {
                    self.selectedBookTable!.simulateBookSelection(book.objectID, allowTableObscuring: allowTableObscuring)
                }
            }
        } else {
            selectedBookTable!.simulateBookSelection(book.objectID, allowTableObscuring: allowTableObscuring)
        }
    }

    override func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        // Scroll to top of table if the selected tab is already selected
        guard let selectedSplitViewController = selectedSplitViewController, item.tag == selectedIndex else { return }

        if selectedSplitViewController.masterNavigationController.viewControllers.count > 1 {
           selectedSplitViewController.masterNavigationController.popToRootViewController(animated: true)
        } else if let topVc = selectedSplitViewController.masterNavigationController.viewControllers.first,
            let topTable = (topVc as? UITableViewController)?.tableView ?? (topVc as? FormViewController)?.tableView,
            topTable.numberOfSections > 0, topTable.contentOffset.y > 0 {
                topTable.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: true)
        }
    }

    func presentImportView(url: URL) {
        // First select the correct tab (Settings)
        selectedTab = .settings
        guard let settingsSplitVC = selectedSplitViewController else { fatalError("Unexpected missing selected view controller") }

        // Dismiss any existing navigation stack (implementation depends on whether the views are split or not)
        settingsSplitVC.popDetailOrMasterToRoot(animated: false)

        // Select the Import Export row to ensure it is highlighted
        guard let settingsVC = settingsSplitVC.masterNavigationController.viewControllers.first as? Settings else {
            fatalError("Missing Settings view controller")
        }
        settingsVC.tableView.selectRow(at: Settings.importExportIndexPath, animated: false, scrollPosition: .none)

        // Instantiate the destination view controller
        guard let importVC = UIStoryboard.ImportExport.instantiateViewController(withIdentifier: "Import") as? Import else {
            fatalError("Missing Import view controller")
        }
        importVC.preProvidedImportFile = url

        // Instantiate the stack of view controllers leading up to the Import view controller
        guard let navigation = UIStoryboard.ImportExport.instantiateViewController(withIdentifier: "Navigation") as? UINavigationController else {
            fatalError("Missing Navigation view controller")
        }
        navigation.setViewControllers([
            UIStoryboard.ImportExport.instantiateViewController(withIdentifier: "ImportExport"),
            importVC
        ], animated: false)

        // Put them on the screen
        settingsSplitVC.showDetailViewController(navigation, sender: self)
    }

    func presentBackupView() {
        // First select the correct tab (Settings)
        selectedTab = .settings
        guard let settingsSplitVC = selectedSplitViewController else { fatalError("Unexpected missing selected view controller") }

        // Dismiss any existing navigation stack (implementation depends on whether the views are split or not)
        settingsSplitVC.popDetailOrMasterToRoot(animated: false)

        // Select the Backup row to ensure it is highlighted
        guard let settingsVC = settingsSplitVC.masterNavigationController.viewControllers.first as? Settings else {
            fatalError("Unexpected view controller type in settings master navigation controller")
        }
        settingsVC.tableView.selectRow(at: Settings.backupIndexPath, animated: false, scrollPosition: .none)

        // Instantiate the destination view controller
        guard let backupVC = UIStoryboard.Backup.instantiateViewController(withIdentifier: "Backup") as? Backup else {
            fatalError("Missing Backup view controller")
        }

        // Instantiate the navigation view controller leading up to the Backup view controller
        guard let navigation = UIStoryboard.Backup.instantiateViewController(withIdentifier: "Navigation") as? UINavigationController else {
            fatalError("Missing Navigation view controller")
        }
        navigation.setViewControllers([backupVC], animated: false)

        // Put them on the screen
        settingsSplitVC.showDetailViewController(navigation, sender: self)
    }
}
