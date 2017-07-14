//
//  FeedViewController.swift
//  Flokk
//
//  Created by Jared Heyen on 11/3/16.
//  Copyright © 2016 Flokk. All rights reserved.
//

import UIKit

class FeedViewController: UIViewController {
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var navigationBar: UINavigationItem!
    @IBOutlet weak var noPostsImageView: UIImageView!
    @IBOutlet weak var noPostsLabel: UILabel!
    
    var group: Group! // The group this feed is reading from - should be a reference
    
    static let initialPostCount = 10 // The initial amount of posts to load
    var loadedPosts = [Post]() // When there are a lot of posts, this will contain only the most 'x' recent posts
    
    let transitionDown = SlideDownAnimator()
    var refreshControl: UIRefreshControl = UIRefreshControl()
    
    var postCount = initialPostCount // Only really matters when there are more than 10 posts
    
    fileprivate var userProfilePhotos = [String : UIImage]()
    
    fileprivate var listenerHandle: UInt!
    
    //fileprivate var imagePicker = UIImagePickerController()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.tableView.delegate = self
        self.tableView.dataSource = self
        self.refreshControl.addTarget(self, action: #selector(FeedViewController.handleRefresh(refreshControl:)), for: UIControlEvents.valueChanged)
        self.refreshControl.tintColor = TEAL_COLOR
        
        self.tableView.refreshControl = self.refreshControl
        
        //self.imagePicker.delegate = self
        
        self.loadedPosts = self.group.posts
        
        self.tableView.estimatedRowHeight = 200
        self.tableView.rowHeight = UITableViewAutomaticDimension
        
        self.tableView.contentInset = UIEdgeInsetsMake(0.0, 0.0, 0.0, 0.0)
        self.edgesForExtendedLayout = .bottom
        
        // Set the navigation bar title to the group name
        self.navigationBar.title = group.name
        
        self.loadPosts() // Load the posts
        self.beginListeners() // Begin listening for changes
        
        // Check if there are no posts, so we know to show the "No Posts" Frowny Face
        if self.group.postsData.keys.count == 0 && self.group.posts.count == 0 { // If there are no posts
            self.noPostsImageView.isHidden = false
            self.noPostsLabel.isHidden = false
            self.refreshControl.endRefreshing() // Don't refresh if there are no posts to load
        }
        
        if self.loadedPosts.count > 0 { // If there are already posts loaded, don't refresh anymore
            self.refreshControl.endRefreshing()
        }
        
        let longPressGesture:UILongPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(FeedViewController.handleLongPress(_:)))
        longPressGesture.minimumPressDuration = 0.5 // 1 second press
        longPressGesture.delegate = self
        self.tableView.addGestureRecognizer(longPressGesture)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        self.loadedPosts = self.group.posts // This might cause problems when we try to implement pagination
        self.tableView.reloadData() // Reload data every time this view appears, in case we just uploaded a phorto
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    @IBAction func unwindToFeed(segue: UIStoryboardSegue) {
    }
    
    @IBAction func uploadPic(_ sender: AnyObject) {
        //imagePicker.allowsEditing = false
        //imagePicker.sourceType = .photoLibrary
        
        //present(imagePicker, animated: true, completion: nil)
    }
    
    // Called when the user pulls down on this table
    func handleRefresh(refreshControl: UIRefreshControl) {
        self.tableView.reloadData()
        
        // Have a little delay here
        refreshControl.endRefreshing()
    }
    
    // Load the posts from the database
    func loadPosts() {
        if self.group.posts.count < self.postCount { // Check if we need to load more posts
            self.refreshControl.beginRefreshing() // Start the refresh control
            
            // I have posts data stored locally, why tf am i doing this
            let groupPostsRef = database.ref.child("groups").child(self.group.id).child("posts")
            groupPostsRef.queryOrdered(byChild: "timestamp").observeSingleEvent(of: .value, with: { (snapshot) in
                if let values = snapshot.value as? [String : [String : Any]] { // Load the posts as a dictionary of dictionaries
                    if values.count == 0 {
                        self.refreshControl.endRefreshing()
                    }
                    
                    for (id, data) in values {
                        let posterHandle = data["poster"] as! String
                        
                        // Load this user's profile photo if it hasn't been loaded already
                        if !self.userProfilePhotos.keys.contains(posterHandle) {
                            let profilePhotoRef = storage.ref.child("users").child(posterHandle).child("profilePhoto.jpg")
                            profilePhotoRef.data(withMaxSize: MAX_PROFILE_PHOTO_SIZE, completion: { (data, error) in
                                if error == nil { // If there wasn't an error
                                    let profilePhoto = UIImage(data: data!) // Load the profile photo from the received data
                                    
                                    self.userProfilePhotos[posterHandle] = profilePhoto
                                    
                                    DispatchQueue.main.async {
                                        self.tableView.reloadData()
                                    }
                                } else {
                                    print(error!)
                                }
                            })
                        }
                        
                        let matches = self.group.loadingPostIDs.filter{$0 == id} // Check if there is a loaded/loading post that matches this ID
                        if matches.count != 0 { // If this post has already been loaded
                            return // Then skip loading this post
                        } else { // This post hasn't been loaded yet, nor has started to load, begin to load it
                            self.group.loadingPostIDs.append(id) // Add this post to the loading posts IDs array to global groups array
                            
                            // Load in the basic data for this post
                            let posterHandle = data["poster"] as! String // Handle for who uploaded this post
                            let timestamp = Date(timeIntervalSinceReferenceDate: (data["timestamp"] as! Double)) // When this post was uploaded
                            //print("timestamp \(timestamp)")
                            
                            // Load the post image
                            let postRef = storage.ref.child("groups").child(self.group.id).child("posts")
                            postRef.child("\(id)/post.jpg").data(withMaxSize: MAX_POST_SIZE, completion: { (data, error) in
                                if error == nil { // If there wasn't an error
                                    let postImage = UIImage(data: data!)
                                    
                                    // Generate the post
                                    let post = Post(posterHandle: posterHandle, image: postImage!, postID: id, timestamp: timestamp)
                                    
                                    // Store it in the various arrays
                                    self.group.posts.append(post)
                                    
                                    // Sort the group posts by the upload date, with the more recent posts first
                                    self.group.posts.sort(by: { $0.timestamp.timeIntervalSinceReferenceDate < $1.timestamp.timeIntervalSinceReferenceDate })
                                    
                                    self.loadedPosts = self.group.posts
                                    
                                    DispatchQueue.main.async {
                                        self.tableView.reloadData()
                                        self.refreshControl.endRefreshing()
                                    }
                                } else { // If there was an error
                                    print(error!)
                                }
                            })
                        }
                    }
                }
            })
        } else { // If all of the posts are loaded
            // Load the poster profile photos
            let groupPostsRef = database.ref.child("groups").child(self.group.id).child("posts")
            groupPostsRef.observeSingleEvent(of: .value, with: { (snapshot) in
                if let values = snapshot.value as? [String : [String : Any]] {
                    for (id, data) in values {
                        let posterHandle = data["poster"] as! String
                        
                        // Load this user's profile photo if it hasn't been loaded already
                        if !self.userProfilePhotos.keys.contains(posterHandle) {
                            let profilePhotoRef = storage.ref.child("users").child(posterHandle).child("profilePhoto.jpg")
                            profilePhotoRef.data(withMaxSize: MAX_PROFILE_PHOTO_SIZE, completion: { (data, error) in
                                if error == nil { // If there wasn't an error
                                    let profilePhoto = UIImage(data: data!) // Load the profile photo from the received data
                                    
                                    self.userProfilePhotos[posterHandle] = profilePhoto
                                    
                                    DispatchQueue.main.async {
                                        self.tableView.reloadData()
                                    }
                                } else {
                                    print(error!)
                                }
                            })
                        }
                    }
                }
            })
        }
    }
    
    // Begin listening for changes in this group
    // That being mainly post uploads, but also comments, group invites, group additions/accepts, someone changing the profile photo
    func beginListeners() {
        let groupRef = database.ref.child("groups").child(self.group.id).child("posts")
        self.listenerHandle = groupRef.queryOrdered(byChild: "timestamp").queryStarting(atValue: Double(NSDate.timeIntervalSinceReferenceDate)).observe(.childAdded, with: { (snapshot) in
            if let values = snapshot.value as? NSDictionary { // If there has actually been a new post
                let postID = snapshot.key
                let posterHandle = values["poster"] as! String
                let timestamp = Date(timeIntervalSinceReferenceDate: (values["timestamp"] as! Double))
                
                let postRef = storage.ref.child("groups").child(self.group.id).child("posts").child(postID)
                postRef.data(withMaxSize: MAX_POST_SIZE, completion: { (data, error) in
                    if error == nil { // If there wasn't an error
                        let postImage = UIImage(data: data!)
                        
                        let post = Post(posterHandle: posterHandle, image: postImage!, postID: postID, timestamp: timestamp)
                        
                        self.group.posts.append(post)
                        
                        DispatchQueue.main.async {
                            self.loadedPosts = self.group.posts
                            self.tableView.reloadData()
                        }
                    } else { // If there was an error
                        print(error!)
                    }
                })
            }
        })
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "segueFromFeedToComment" {
            if let commentView = segue.destination as? AddCommentViewController {
                if let tag = (sender as? FeedTableViewCell)?.tag {
                    let post = loadedPosts[tag]
                    
                    commentView.post = post
                    commentView.group = self.group
                }
            }
        } else if segue.identifier == "segueFromFeedToPhotoUploadPage" {
            if let photoUploadPageView = segue.destination as? PhotoUploadPageViewController {
                photoUploadPageView.groupToPass = group

            }
        } else if segue.identifier == "segueFromFeedToGroupSettings" {
            if let groupSettings = segue.destination as? GroupSettingsViewController {
                groupSettings.group = self.group
            }
        }
    }
}


// Table View Functions
extension FeedViewController: UITableViewDataSource, UITableViewDelegate {
    // Try to adjust the size of each cell according to the size of the picture
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "default", for: indexPath as IndexPath) as! FeedTableViewCell
        
        let index = loadedPosts.count - 1 - indexPath.row
        cell.tag = index // Set the tag so prepare for segue can recognize which post was selected
        
        let post = loadedPosts[index]
        
        cell.setCustomImage(image: post.image)
        
        // Set the poster's profile photo & crop it to a circle
        cell.userImage.image = self.userProfilePhotos[post.posterHandle] ?? UIImage(named: "AddProfilePic")
        cell.userImage.layer.cornerRadius = cell.userImage.frame.size.width / 2
        cell.userImage.clipsToBounds = true
        
        // If this post is currently selected to be saveds
        if loadedPosts[indexPath.row].selectedToSave {
            // Resize it to be 5 pixels smaller, everywhere
            let frame = cell.imageView?.frame
            
            cell.postedImage?.frame = CGRect(x: (frame?.origin.x)! + 10, y: (frame?.origin.y)! + 10, width: (frame?.size.width)! - 5, height: (frame?.size.height)! - 5)
        }
        
        // Then adjust the size of the cell according to the photos - this is done in the FeedTableViewCell class
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return loadedPosts.count
    }
}

// Delegates for holding posts to save them
extension FeedViewController: UIGestureRecognizerDelegate, UIActionSheetDelegate {
    // Check for a cell being held
    func handleLongPress(_ longPressGestureRecognizer: UILongPressGestureRecognizer) {
        if longPressGestureRecognizer.state == UIGestureRecognizerState.began {
            let touchPoint = longPressGestureRecognizer.location(in: self.view)
            if let indexPath = tableView.indexPathForRow(at: touchPoint) {
                let row = indexPath.row
                let post = loadedPosts[row]
                
                loadedPosts[row].selectedToSave = true
                
                self.tableView.reloadData() // Update the table view so the selected cells are updated
                
                // Display the action sheet so the user can decide whether/where to save the postr
                showActionSheet(post: post)
            }
        }
    }
    
    // Show the action sheet to decide where to save the selected post(s)
    func showActionSheet(post: Post) {
        // Create the AlertController and add Its action like button in Actionsheet
        let actionSheetControllerIOS8: UIAlertController = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        
        // Create the cancel button
        let cancelActionButton = UIAlertAction(title: "Cancel", style: .cancel) {
            (_) in
            
        }
        
        // Create the save to library button
        let saveToCameraRollButton = UIAlertAction(title: "Save to Camera Roll", style: .default) {
            (_) in
            
            // Attempt to save the image to the library
            UIImageWriteToSavedPhotosAlbum(post.image, self, #selector(self.image(_:didFinishSavingWithError:contextInfo:)), nil)
        }
        
        // Create the save to Flokk button
        let saveToFlokkButton = UIAlertAction(title: "Save to Flokk", style: .default) {
            (_) in
            
        }
        
        // Add all of the buttons to the action sheet
        actionSheetControllerIOS8.addAction(cancelActionButton)
        actionSheetControllerIOS8.addAction(saveToCameraRollButton)
        actionSheetControllerIOS8.addAction(saveToFlokkButton)
        
        self.present(actionSheetControllerIOS8, animated: true, completion: nil)
    }
    
    // Add image to Library
    func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        if let error = error {
            // we got back an error!
            let ac = UIAlertController(title: "Save error", message: error.localizedDescription, preferredStyle: .alert)
            ac.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(ac, animated: true)
        } else {
            let ac = UIAlertController(title: "Saved!", message: "The image has been saved to your photos.", preferredStyle: .alert)
            ac.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(ac, animated: true)
        }
    }
}

class FeedTableViewCell: UITableViewCell/*, UIScrollViewDelegate */ {
    @IBOutlet weak var userImage: UIImageView!
    @IBOutlet weak var postedImage: UIImageView!
    
    var selectedToSave: Bool = false // Whether this cell has been selected to be saved or not
    
    // Internally calculate the constraint for this aspect fit
    internal var aspectConstraint : NSLayoutConstraint? {
        didSet {
            if oldValue != nil {
                postedImage.removeConstraint(oldValue!)
            }
            
            if aspectConstraint != nil {
                postedImage.addConstraint(aspectConstraint!)
            }
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        aspectConstraint = nil
    }
    
    // Sets the custom constraints for this
    func setCustomImage(image: UIImage) {
        let aspect = image.size.width / image.size.height
        let constraint = NSLayoutConstraint(item: postedImage, attribute: NSLayoutAttribute.width, relatedBy: NSLayoutRelation.equal, toItem: postedImage, attribute: NSLayoutAttribute.height, multiplier: aspect, constant: 0.0)
        constraint.priority = 999
        
        aspectConstraint = constraint
        
        postedImage.image = image
    }
}

// Tf is this used for
enum FeedTableViewCellSide {
    case FeedTableViewCellSideLeft
    case FeedtableViewCellSideRight
}
