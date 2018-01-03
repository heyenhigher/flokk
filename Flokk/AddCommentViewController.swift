//
//  AddCommentViewController.swift
//  Flokk
//
//  Created by Jared Heyen on 2/11/17.
//  Copyright © 2017 Flokk. All rights reserved.
//

import UIKit

class AddCommentViewController: UIViewController {
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var textField: UITextField!
    @IBOutlet weak var profilePhotoBarButton: UIBarButtonItem!
    @IBOutlet weak var noCommentsLabel: UILabel!
    @IBOutlet weak var posterImage: UIImageView!
    @IBOutlet weak var fullNameLabel: UILabel!
    @IBOutlet weak var datePostedLabel: UILabel!
    
    @IBOutlet var keyboardHeightLayoutConstraint : NSLayoutConstraint?
    
    var loadedComments = [Comment]()
    
    var post: Post! // A copy of the post
    var group: Group!
    
    var userProfilePhotos = [String : UIImage]() // Dict of all of the according profile photos
    
    // If the comments have been checked yet
    private var checkedForComments = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.hideKeyboardWhenTappedAround()
        
        self.tableView.delegate = self
        self.tableView.dataSource = self
        self.textField.delegate = self
        
        // Get the date the post was uploaded
        let date = post.timestamp!
        let calendar = Calendar.current
        
        let month = date.getMonth()
        let day = date.getDay()
        let year = date.getYear()
        
        // Get the individual components from the most recent post
        var hour = date.getHour()
        let minutes = date.getMinute()
        
        // check if this was in the AM or PM
        var amPM = "AM"
        if hour > 12 {
            amPM = "PM"
            hour -= 12
        }
        
        // Check how recent this post was
        // If it was under an hour ago
        
        
        
        // Tells the notification to
        NotificationCenter.default.addObserver(self, selector: #selector(self.keyboardNotification(notification:)), name: NSNotification.Name.UIKeyboardWillChangeFrame, object: nil)
        
        // Load in the poster's profile photo
        let userRef = storage.ref.child("users").child(self.post.poster.uid).child("profilePhotoIcon.jpg")
        userRef.data(withMaxSize: MAX_PROFILE_PHOTO_SIZE, completion: { (data, error) in
            if error == nil { // If there wasn't an error
                let profilePhoto = UIImage(data: data!)
                
                self.post.poster.profilePhoto = profilePhoto!
                
                self.posterImage.image = profilePhoto!
            } else { // If there was an error
                // TODO: Handle the error if the profile photo didnt load correctly
                print(error!)
            }
        })
        
        // Load in the comments, ordered by most recent?
        let commentRef = database.ref.child("comments").child(self.group.id).child(post.id)
        commentRef.observeSingleEvent(of: .value, with: { (snapshot) in
            if let children = snapshot.value as? [String : Any] {
                for (key, data) in children { // Iterate through all of the comments
                    if let values = data as? NSDictionary {
                        let commenterHandle = values["poster"] as! String
                        let content = values["content"] as! String
                        let timestamp = NSDate(timeIntervalSinceReferenceDate: values["timestamp"] as! Double)
                        
                        let comment = Comment(userHandle: commenterHandle, content: content, timestamp: timestamp)
                        
                        // Add the comments
                        self.loadedComments.append(comment)
                        
                        // Sort the comments, ascending, so the oldest ones appear at the top
                        self.loadedComments.sort(by: { $0.timestamp.timeIntervalSinceReferenceDate > $1.timestamp.timeIntervalSinceReferenceDate })
                        
                        // Load in the profile photo for the commenter
                        if !self.userProfilePhotos.keys.contains(commenterHandle) { // If we haven't loaded this user's profile photo already
                            let profilePhotoRef = storage.ref.child("users").child(commenterHandle).child("profilePhotoIcon.jpg")
                            profilePhotoRef.data(withMaxSize: MAX_PROFILE_PHOTO_SIZE, completion: { (data, error) in
                                if error == nil { // If there wasn't an error
                                    let profilePhoto = UIImage(data: data!)
                                    
                                    // Set the according profile in the dict
                                    self.userProfilePhotos[commenterHandle] = profilePhoto
                                    
                                    DispatchQueue.main.async {
                                        self.tableView.reloadData()
                                    }
                                } else { // If there was an error
                                    print(error!)
                                }
                            })
                        } else { // If the commenters profile photod has already been loaded
                            // Then we can immediately refresh the able view
                            DispatchQueue.main.async {
                                self.tableView.reloadData()
                            }
                        }
                    }
                }
            }
        })
        
        self.checkedForComments = true
        
        self.checkCommentsCount()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // If we've already checked for comments
        if self.checkedForComments {
            // Check if we should show the no comments icon or not
            self.checkCommentsCount()
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    @IBAction func posterProfile(_ sender: Any) {
        
    }
    
    // Check if we should show the no comments icon or not
    private func checkCommentsCount() {
        if self.loadedComments.count == 0 {
            self.noCommentsLabel.isHidden = false
        } else {
            self.noCommentsLabel.isHidden = true
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let feedNav = segue.destination as? FeedNavigationViewController {
            //feedNav.groupToPass = post.postedGroup
        }
    }
}

// MARK: Table View Functions
extension AddCommentViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "default", for: indexPath as IndexPath) as! CommentsTableViewController
        
        let comment = self.loadedComments[indexPath.row]
        cell.userPhotoView.image = self.userProfilePhotos[comment.userHandle]
        cell.userPhotoView.layer.cornerRadius = cell.userPhotoView.frame.size.width / 2
        cell.userPhotoView.clipsToBounds = true
        
        cell.contentTextView.text = comment.content
        
        cell.contentTextView.isUserInteractionEnabled = false
        cell.contentTextView.isEditable = false
        
        return cell
    }
    
    // The number of rows depends on how many comments there are
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.loadedComments.count
    }
}

// MARK: Text Field Functions
extension AddCommentViewController: UITextFieldDelegate {
    // So the text field doesnt try to line break when we press enter
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        
        // Upload the comment
        let commentKey = database.ref.child("comments").child(self.group.id).child(post.id).childByAutoId().key
        let commentRef = database.ref.child("comments").child(self.group.id).child(post.id).child(commentKey) // Database reference
        commentRef.child("poster").setValue(mainUser.uid) // The handle of the commenter, always going to be the mainUser
        commentRef.child("content").setValue(textField.text!) // The actual content of the comment
        commentRef.child("timestamp").setValue(NSDate.timeIntervalSinceReferenceDate)
        
        // Added the comment to the view locally
        self.loadedComments.append(Comment(userHandle: mainUser.handle, content: textField.text!, timestamp: NSDate(timeIntervalSinceReferenceDate: NSDate.timeIntervalSinceReferenceDate)))
        self.tableView.reloadData()
        
        return true
    }
    
    // Whenever the keyboard is activated, this notifies the textField to shift upward with the keyboard
    // I got this entire code somewhere from stack overflow
    func keyboardNotification(notification: NSNotification) {
        if let userInfo = notification.userInfo {
            let endFrame = (userInfo[UIKeyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
            let duration:TimeInterval = (userInfo[UIKeyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0
            let animationCurveRawNSN = userInfo[UIKeyboardAnimationCurveUserInfoKey] as? NSNumber
            let animationCurveRaw = animationCurveRawNSN?.uintValue ?? UIViewAnimationOptions.curveEaseInOut.rawValue
            let animationCurve:UIViewAnimationOptions = UIViewAnimationOptions(rawValue: animationCurveRaw)
            
            if (endFrame?.origin.y)! >= UIScreen.main.bounds.size.height {
                self.keyboardHeightLayoutConstraint?.constant = 0.0
            } else {
                self.keyboardHeightLayoutConstraint?.constant = endFrame?.size.height ?? 0.0
            }
            
            UIView.animate(withDuration: duration, delay: TimeInterval(0), options: animationCurve, animations: { self.view.layoutIfNeeded() }, completion: nil)
        }
    }
}

class CommentsTableViewController: UITableViewCell {
    @IBOutlet weak var userPhotoView: UIImageView!
    @IBOutlet weak var contentTextView: UITextView!
}
