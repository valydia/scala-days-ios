/*
* Copyright (C) 2015 47 Degrees, LLC http://47deg.com hello@47deg.com
*
* Licensed under the Apache License, Version 2.0 (the "License"); you may
* not use this file except in compliance with the License. You may obtain
* a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

import UIKit
import MobileCoreServices
import AddressBook
import ZBarSDK

class SDContactViewController: GAITrackedViewController,
                                ZBarReaderDelegate,
                                UINavigationControllerDelegate,
                                UIImagePickerControllerDelegate,
                                SDQRScannerOverlayViewDelegate,
                                UIAlertViewDelegate {

    lazy var scannerVC = ZBarReaderViewController()
    let kTagForRequestAlertView = 666
    let kImgIconTopSpaceForSmallerIphones : CGFloat = 20.0
    var currentVCardString = ""
    
    @IBOutlet weak var lblScanResult: UILabel!
    @IBOutlet weak var imgIcon: UIImageView!
    @IBOutlet weak var constraintForImgTopSpace: NSLayoutConstraint!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.setNavigationBarItem()
        self.title = NSLocalizedString("contacts", comment: "Contact")
        drawRegularFeedback()
        
        self.screenName = kGAScreenNameContact
    }

    // MARK: - QR Code scanning logic
    
    @IBAction func didTapScanButton() {
        scannerVC.readerDelegate = self
        scannerVC.readerView.torchMode = 0
        // Disabled recognition of rarely used I2/5 symbology to improve performance:
        scannerVC.scanner.setSymbology(ZBAR_I25, config: ZBAR_CFG_ENABLE, to: 0)
        scannerVC.showsZBarControls = false
        let scannerVCOverlayView = SDQRScannerOverlayView(frame: self.view.frame)
        scannerVCOverlayView.delegate = self
        scannerVC.cameraOverlayView = scannerVCOverlayView
        
        self.present(scannerVC, animated: true, completion: nil)
        
        SDGoogleAnalyticsHandler.sendGoogleAnalyticsTrackingWithScreenName(kGAScreenNameContact, category: nil, action: kGAActionContactScanContact, label: nil)
    }
    
    func readerControllerDidFail(toRead reader: ZBarReaderController!, withRetry retry: Bool) {
        self.handleResultsFromAddressBookWithErrorMessage(.invalidVCardData)
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        scannerVC.dismiss(animated: true, completion: nil)
        let results = info[ZBarReaderControllerResults] as! ZBarSymbolSet
        if results.count > 0 {
            for symbol in results {
                if (symbol as! ZBarSymbol).data != nil {
                    processQRScan((symbol as AnyObject).data)
                    return
                }
            }
        } else {
            self.handleResultsFromAddressBookWithErrorMessage(.invalidVCardData)
            return
        }
    }
    
    func didTapCancelButtonInQRScanner() {
        scannerVC.dismiss(animated: true, completion: nil)
    }
    
    func processQRScan(_ result: String?) {
        if let successfulResult = result {
            saveContactFromVCardString(successfulResult)
        } else {
            self.handleResultsFromAddressBookWithErrorMessage(.invalidVCardData)
        }
    }
    
    // MARK: - VCard handling
    
    func saveContactFromVCardString(_ vCardString: String) {
        if let book: ABAddressBook = ABAddressBookCreateWithOptions(nil, nil).takeRetainedValue() {
            switch(ABAddressBookGetAuthorizationStatus()) {
            case .notDetermined:
                ABAddressBookRequestAccessWithCompletion(book) {
                    (granted:Bool, err:CFError!) in
                    if granted {
                        self.showAlertToRequestContactAddWithContactName(SDContactCreationHelper.contactName(fromVCardString: vCardString), vCardString: vCardString)
                    } else {
                        self.drawErrorWithMessage(NSLocalizedString("contacts_regular_feedback_error_no_access", comment: ""))
                    }
                }
            case .authorized:
                self.showAlertToRequestContactAddWithContactName(SDContactCreationHelper.contactName(fromVCardString: vCardString), vCardString: vCardString)
            default:
                self.drawErrorWithMessage(NSLocalizedString("contacts_regular_feedback_error_no_access", comment: ""))
            }
        }        
    }
    
    // MARK: - UI changes for feedback
        
    func handleResultsFromAddressBookWithErrorMessage(_ error: SDContactCreationHelperError) {
        switch(error) {
        case .noError:
            drawRegularFeedback()
            showAlertForContactAddSuccess()
        case .invalidVCardData:
            drawErrorWithMessage(NSLocalizedString("contacts_regular_feedback_error_invalid_qr_code", comment: ""))
        default:
            drawErrorWithMessage(NSLocalizedString("contacts_regular_feedback_error_unknown", comment: ""))
        }
        currentVCardString = ""
    }
    
    func drawErrorWithMessage(_ message: String) {
        imgIcon?.image = UIImage(named: "placeholder_error")
        lblScanResult?.text = message
    }
    
    func drawRegularFeedback() {
        imgIcon?.image = UIImage(named: "placeholder_contact")
        lblScanResult?.text = NSLocalizedString("contacts_regular_feedback_message", comment: "")
        if IS_IPHONE5 {
            constraintForImgTopSpace.constant = kImgIconTopSpaceForSmallerIphones
        }
    }
    
    // MARK: - Alert views
    
    func showAlertToRequestContactAddWithContactName(_ contactName: String?, vCardString: String) {
        var message : String
        if let properName = contactName {
            message = NSString(format: NSLocalizedString("contacts_add_contact_request", comment: "") as NSString, properName as String) as String
        } else {
            message = NSLocalizedString("contacts_add_contact_request_no_name", comment: "")
        }
        currentVCardString = vCardString
        
        SDAlertViewHelper.showSimpleAlertViewOnViewController(self, title: "", message: message, cancelButtonTitle: NSLocalizedString("common_cancel", comment: ""), otherButtonTitle: NSLocalizedString("common_ok", comment: ""), tag: kTagForRequestAlertView, delegate: self) { (alertAction) -> Void in
            if alertAction?.style != .cancel {
                SDContactCreationHelper.createContactInAddressBook(fromVCardString: vCardString, completion: { (error) -> Void in
                    self.handleResultsFromAddressBookWithErrorMessage(error)
                })
            }
        }
    }
    
    func showAlertForContactAddSuccess() {
        SDAlertViewHelper.showSimpleAlertViewOnViewController(self, title: nil, message: NSLocalizedString("contacts_add_contact_success_message", comment: ""), cancelButtonTitle: NSLocalizedString("common_ok", comment: ""), otherButtonTitle: nil, tag: 0, delegate: nil, handler: nil)
    }
    
    // MARK: - Alert view delegate
    
    func alertView(_ alertView: UIAlertView, clickedButtonAt buttonIndex: Int) {
        if alertView.tag == kTagForRequestAlertView && buttonIndex != alertView.cancelButtonIndex {
            SDContactCreationHelper.createContactInAddressBook(fromVCardString: currentVCardString, completion: { (error) -> Void in
                self.handleResultsFromAddressBookWithErrorMessage(error)
            })
        }
    }
    
}
