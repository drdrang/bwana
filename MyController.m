//
//  MyController.m

// Conor Dearden, Daniel Jalkut, Mark Johnston, FZiegler

#import "MyController.h"


// HTML Code that gets inserted for header and footer of page. Includes CSS attributes and search field header 
#define HTML_HEADER_INDEX @"<html><head><meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\"><title>Manual Pages</title><style type=\"text/css\">.blueBox{ background-color: #F1F5F9;padding: 6px 10px 6px 10px; border: 1px #ccc double; color: #000000; font-size: 14px}.indexLink {float:right; margin-top:4px;}</style></head><body><form name=\"form1\" method=\"get\" action=\"man:\"><div class=\"blueBox\"><a class=\"indexLink\" href=\"man:index_refresh%@\">Refresh</a>man: <input name=\"a\" type=\"text\"><input type=\"submit\" value=\"Search\"></div></form> "

#define HTML_HEADER_MAN @"<html><head><meta http-equiv=\"Content-Type\" content=\"text/html;charset=iso-8859-1\"><title>Manual Page for %@</title><style type=\"text/css\">.red {color: #CC0000} .hed {color: #000000; font-weight: bold; font-size: larger;}.blueBox{ background-color: #F1F5F9;padding: 6px 10px 6px 10px; border: 1px #ccc double; color: #000000; font-size: 14px}.indexLink {float:right; margin-top:4px;}</style></head><body><form name=\"form1\" method=\"get\" action=\"man:\"><div class=\"blueBox\"><a class=\"indexLink\" href=\"man:\">Index</a>man: <input name=\"a\" type=\"text\"><input type=\"submit\" value=\"Search\"></div></form><pre> "

#define HTML_FOOTER @"<div align=\"center\" class=\"blueBox\">Bwana Created by <a href=\"http://www.bruji.com/\">Bruji</a></div></body></html> "


@interface MyController (private)
- (void)showManualPage:(NSString *)manualPage inNewWindow:(BOOL)openInNewWindow;
- (NSString *)manualPageFor:(NSString *)manualPage section:(NSString *)section;
- (NSString *)unzip:(NSString *)aPath;
- (NSString *)asciiFormatForManualPath:(NSString *)manualPagePath;
- (NSString *)formatForHTML:(NSString *)asciiFormatedInput manual:(NSString *)manualPage;
- (void)openInBrowserThePath:(NSString *)aPath inNewWindow:(BOOL)openInNewWindow;
- (void)handleAppleEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent;
- (void) showIndexWithFilter:(NSString*)indexFilter inNewWindow:(BOOL)openInNewWindow;
- (void) showIndexWithFilter:(NSString*)indexFilter inNewWindow:(BOOL)openInNewWindow usingCache:(BOOL)useCache;
- (BOOL)isLeopard;
- (NSMutableString *)encodeForHTML:(NSString *)aString;
@end

@implementation MyController

#pragma mark -
#pragma mark Service Menu
- (void)searchFor:(NSPasteboard *)pboard userData:(NSString *)data error:(NSString **)error {
	NSString *searchTerm;
	if ([[pboard types] containsObject:NSStringPboardType]){
        searchTerm = [pboard stringForType:NSStringPboardType];
        if (searchTerm && ![searchTerm isEqualToString:@""])  {
			[self showManualPage:searchTerm inNewWindow:NO];
		}
	}
}


#pragma mark Apple Event
- (void)handleAppleEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent {
	dontDisplayWindow = YES;
	NSString *URLString = [[event paramDescriptorForKeyword:keyDirectObject] stringValue];
	URLString = [URLString stringByReplacingPercentEscapesUsingEncoding:NSASCIIStringEncoding];
		
	//Find out what browser called it
	[callingApplication release];
	callingApplication = [[[[NSWorkspace sharedWorkspace] activeApplication] objectForKey:@"NSApplicationName"] retain];
	
	//Remove and prefix that is not relevant
	//Remove and prefix that is not relevant
	if ([URLString hasPrefix:@"x-man-page://"])
		URLString = [URLString substringFromIndex:13];
	if ([URLString hasPrefix:@"man:"]) {
		URLString = [URLString substringFromIndex:4];
		if ([URLString hasPrefix:@"//"])
			URLString = [URLString substringFromIndex:2];
		//From the form post
		if ([URLString hasPrefix:@"?a="])
			URLString = [URLString substringFromIndex:3];
	}
	
	// Call the index if it's blank and call it with an object to refresh it 
	// Also do a filter search on the index with man:foo.?
	if ([URLString isEqualToString:@""])
		[self masterIndex:nil];
	else if ([URLString hasPrefix:@"index_refresh"] || [URLString hasSuffix:@".?"])
	{
		NSString *filter = nil;
				
		// if the URLString is just "index_refresh" then we don't have a filter,
		// otherwise we parse the filter off the end
		if ([URLString isEqualToString:@"index_refresh"] == NO)
		{
			if ([URLString hasSuffix:@".?"])
				filter = [URLString substringToIndex:[URLString length] -2];
			else {
				NSRange prefixRange = [URLString rangeOfString:@"index_refresh"];
				filter = [URLString substringFromIndex:prefixRange.length];
			}
		}
		[self showIndexWithFilter:filter inNewWindow:NO usingCache:NO];		
	}
	else 
		[self showManualPage:URLString inNewWindow:NO];
	
}

#pragma mark -
#pragma mark Main Functions
- (void)showManualPage:(NSString *)manualPage inNewWindow:(BOOL)openInNewWindow {
	NSFileManager *manager = [NSFileManager defaultManager];
	NSString *section = nil, *tempLocationOfFile;
	BOOL foundManPage = NO;
		
	//check for shell command injections and cut string short
	NSCharacterSet *charSet = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz:-_.0123456789/"];
	charSet = [charSet invertedSet];
	int aLocation;
	if ((aLocation = [manualPage rangeOfCharacterFromSet:charSet].location) != NSNotFound ) {
		manualPage = [manualPage substringToIndex:aLocation];
	}
	
	// Separate the section part from the manual page
	// If the path has slashes in it, it's a path directly do not seperate the section at the end.
	if ([manualPage rangeOfString:@"/" options:NSLiteralSearch].location == NSNotFound) {
		if ((aLocation = [manualPage rangeOfString:@"." options:NSBackwardsSearch].location) != NSNotFound) {
			section = [manualPage substringFromIndex:aLocation +1];
			
			NSCharacterSet *sectionCharSet = [NSCharacterSet characterSetWithCharactersInString:@"0123456789nlpo"];
			
			//The section should be 1-9, n, p, l, o, 0p, 1p, 3p or tcl. Otherwise leave intact
			if ([section length] == 1 && [section rangeOfCharacterFromSet:sectionCharSet].location != NSNotFound || [section isEqualToString:@"tcl"] || [section isEqualToString:@"0p"] || [section isEqualToString:@"1p"] || [section isEqualToString:@"2p"]) {
				manualPage = [manualPage substringToIndex:aLocation];
			}
			else 
				section = nil;
		}
	}

	// Creeate the path to save the file at
	if (section)
		tempLocationOfFile = [NSString stringWithFormat:@"%@/%@.%@.html", cachesFolder, [manualPage lastPathComponent], section];
	else
		tempLocationOfFile = [NSString stringWithFormat:@"%@/%@.html", cachesFolder, [manualPage lastPathComponent]];
		
	// If the file doesn't exist in the path then we need to create it from the manual pages
	// ### For debbugging turn this off as the caching of pages can confuse
	if ([manager fileExistsAtPath:tempLocationOfFile]) {
		// redo caches for pages older than a month
		NSDictionary *fileAttributes = [manager fileAttributesAtPath:tempLocationOfFile traverseLink:NO];
		NSDate *modificationDate = [fileAttributes objectForKey:NSFileModificationDate];
		if ([modificationDate timeIntervalSinceNow] > -2592000.00) // a month
			foundManPage = YES;
	}
	
	if (foundManPage == NO) {
		//Ask man for the path to the page
		NSString *manualPagePath = [self manualPageFor:manualPage section:section];
		
		if (manualPagePath) {
			NSString *manFile = [NSString stringWithContentsOfFile:manualPagePath];
			
			//It's a redirection
			if ([manFile hasPrefix:@".so"]) {
				NSArray *parts = [manFile componentsSeparatedByString:@"\n"];
				parts = [[parts objectAtIndex:0] componentsSeparatedByString:@" "];
				manualPagePath = [NSString stringWithFormat:@"%@/%@", [manualPagePath stringByDeletingLastPathComponent], [parts objectAtIndex:1]];
			}
			
			//Get Ascii man page
			NSString *asciiFormatedOutput = [self asciiFormatForManualPath:manualPagePath];
			
			// If successful, turn it into HTML and save it to disk
			if (asciiFormatedOutput) {
				NSString *HTMLFormatted = [self formatForHTML:asciiFormatedOutput manual:manualPage];	
				[HTMLFormatted writeToFile:tempLocationOfFile atomically:NO];
				foundManPage = YES;
			}
		}
	}
	
	//Daniel Jalkut: filtered index if not found
	if (foundManPage == NO)
	{
		[self showIndexWithFilter:manualPage inNewWindow:openInNewWindow];
	}
	else
	{
		[self openInBrowserThePath:tempLocationOfFile inNewWindow:openInNewWindow];
	}
	[NSApp terminate:self];	
}

- (NSString *)formatForHTML:(NSString *)asciiFormatedInput manual:(NSString *)manualPage {

	NSMutableString *webPage = [NSMutableString string];
		
	//header of web file
	[webPage appendString:[NSString stringWithFormat:HTML_HEADER_MAN, manualPage]];
	

	
	int count = [asciiFormatedInput length], noEight = 0, noUnderline = 0;
	BOOL checkForUnderline = NO, checkForRed = NO;
	
	int i;
	for (i = 0; i < count ; i++) {
		
		if (checkForUnderline) {
			if(noUnderline == 1) {
				if ([asciiFormatedInput characterAtIndex:i] != 95) {
					[webPage appendString:@"</u>"];
					checkForUnderline = NO;		
					noUnderline = 0;
				}
			}
			else
				noUnderline++;
		}
		
		if (checkForRed) {
			if(noEight == 1) {
				if ([asciiFormatedInput characterAtIndex:i] != 8 /*|| ([asciiFormatedInput characterAtIndex:i-1] == 95 && [asciiFormatedInput characterAtIndex:i+1] != 95) */) {
//					if ([webPage hasSuffix:@"</u>"])
//						[webPage insertString:@"</span>" atIndex:[webPage length]-4];
//					else 
					if ([webPage hasSuffix:@"<u>"])
						[webPage insertString:@"</span>" atIndex:[webPage length]-3];
					else
						[webPage insertString:@"</span>" atIndex:[webPage length]-1];

					checkForRed = NO;		
					noEight = 0;
				}
			}
			else
				noEight++;
		}
		
		if ([asciiFormatedInput characterAtIndex:i] == 8) {
			//red
			if (!checkForRed) {
				if ([webPage hasSuffix:@">"])
					[webPage appendString:@"<span class=\"red\">"];
				else if ([webPage hasSuffix:@"&lt;"])
					[webPage insertString:@"<span class=\"red\">" atIndex:[webPage length]-4];
				else if ([webPage hasSuffix:@"&gt;"]) // By Mark Johnston
					[webPage insertString:@"<span class=\"red\">" atIndex:[webPage length]-4];
				else
					[webPage insertString:@"<span class=\"red\">" atIndex:[webPage length]-1];
				
				checkForRed = YES;
			}
			i++;
			noEight = 0;
		}
		else if ([asciiFormatedInput characterAtIndex:i] == 95) {
			if ([asciiFormatedInput characterAtIndex:i +1] == 8) {
				//underline
				if ([asciiFormatedInput characterAtIndex:i +2] == 95) {
					[webPage appendString:@"_"];
					//i += 2;
					//noEight = 0;
				}
				else {
				
					if (!checkForUnderline) {
						[webPage appendString:@"<u>"];
						checkForUnderline = YES;
					}
					i++;
					noUnderline = 0;

				}
				//noUnderline = 0;
			}
			else {
				[webPage appendString:@"_"];
			}
		}
		else {
			
			//http and mailto as well as < >
			if ([asciiFormatedInput characterAtIndex:i] == '<') {
				unsigned int count = [asciiFormatedInput length];
				BOOL email = NO, htmlPage = NO;
				if (i +6 < count) {

					if ([[asciiFormatedInput substringWithRange:NSMakeRange(i, 6)] isEqualToString:@"<http:"]) {
						htmlPage = YES;
					}
					else {
						int j;
						for (j =i; j < i+15 && j < count; j++) {
							if ([asciiFormatedInput characterAtIndex:j] == '>')
								break;
							if ([asciiFormatedInput characterAtIndex:j] == '@') {
								email = YES;
								break;
							}
						}
					}
					
					if (email || htmlPage) {
						
						unsigned int end = [asciiFormatedInput rangeOfString:@">" options:NSLiteralSearch range:NSMakeRange(i, count - i)].location;
						if (end != NSNotFound) {
							NSMutableString *link = [NSMutableString string];
							[link setString:[asciiFormatedInput substringWithRange:NSMakeRange(i+1, (end -i) -1)]];
							i = end;
							unsigned int loc;
							while ((loc = [link rangeOfString:[NSString stringWithFormat:@"%c", 8]].location) != NSNotFound) {
								[link deleteCharactersInRange:NSMakeRange(loc, 2)];
							}
							
							if (email)
								[webPage appendString:[NSString stringWithFormat:@"<a href=\"mailto:%@\">%@</a>", link, link]];
							else if (htmlPage) {
								[webPage appendString:[NSString stringWithFormat:@"<a href=\"%@\">%@</a>", link, link]];
							}
						}
					}
				}
				if (!email && !htmlPage)
					[webPage appendString:@"&lt;"];

			}
			else if ([asciiFormatedInput characterAtIndex:i] == '>') {
				[webPage appendString:@"&gt;"];
			}
			else {
				
				
				
				
				[webPage appendString:[NSString stringWithFormat:@"%c", [asciiFormatedInput characterAtIndex:i]]];
				
				//makeLinks
				if ([asciiFormatedInput characterAtIndex:i] == ')') {
					int end = [webPage length];
					if ([webPage characterAtIndex:end-3] == '(') {
						if ([webPage characterAtIndex:end-2] >48 && [webPage characterAtIndex:end-2] < 58) {
							//do replacement
							int j, lengthMan = 0;
							BOOL continueB = YES;
							for (j = end -4; continueB && j > 0 ; j--) {
								if ([webPage characterAtIndex:j] == ' ') {
									NSMutableString *manCommand = [NSMutableString string];
									[manCommand setString:[webPage substringWithRange:NSMakeRange(j+1, lengthMan)]];
									[manCommand replaceOccurrencesOfString:@"</span>" withString:@"" options:NSLiteralSearch range:NSMakeRange(0,[manCommand length])];
									int replacedRed = [manCommand replaceOccurrencesOfString:@"class=\"red\">" withString:@"" options:NSLiteralSearch range:NSMakeRange(0,[manCommand length])];
									
									NSMutableString *manClean = [NSMutableString string];
									[manClean setString:manCommand];
									[manClean replaceOccurrencesOfString:@"<u>" withString:@"" options:NSLiteralSearch range:NSMakeRange(0, [manClean length])];
									[manClean replaceOccurrencesOfString:@"</u>" withString:@"" options:NSLiteralSearch range:NSMakeRange(0, [manClean length])];
									
									
									NSString *htmlLink = [NSString stringWithFormat:@"<a href=\"man:%@.%c\">%@(%c)</a>", manClean, [webPage characterAtIndex:end-2], manCommand, [webPage characterAtIndex:end-2]];
									[webPage deleteCharactersInRange:NSMakeRange(j +1, lengthMan + 3)];
									if (replacedRed)
										[webPage deleteCharactersInRange:NSMakeRange(j-5, 6)];
									[webPage appendString:htmlLink];
									continueB = NO;
								}
								lengthMan++;
							}
							
						}
					}
				}
			}
			
			
			
		}
	}
	
	if (checkForUnderline) {
		[webPage appendString:@"</u>"];
	}
	if (checkForRed) {
		[webPage appendString:@"</span>"];
	}
	
	
	// Change the headers from red CSS style to the dark CSS style
	// They are regonized as they are preceded by a new line
	[webPage replaceOccurrencesOfString:@"\n<span class=\"red\">" withString:@"\n<span class=\"hed\">" options:NSLiteralSearch range:NSMakeRange(0, [webPage length])];
	
	//[webPage replaceOccurrencesOfString:@"<span class=\"hed\">SEE</span> <span class=\"red\">" withString:@"<span class=\"hed\">SEE</span> <span class=\"hed\">" options:NSLiteralSearch range:NSMakeRange(0, [webPage length])];
	
	NSRange section;
	section = [webPage rangeOfString:@"<span class=\"hed\">"];
	while (section.location != NSNotFound) {
		//check to the end of line
		NSRange newLine = [webPage rangeOfString:@"\n" options:NSLiteralSearch range:NSMakeRange(section.location, [webPage length] - section.location)];
		[webPage replaceOccurrencesOfString:@"</span> <span class=\"red\">" withString:@" " options:NSLiteralSearch range:NSMakeRange(section.location, (newLine.location - section.location) - 6)];
		
		//search again
		section = [webPage rangeOfString:@"<span class=\"hed\">" options:NSLiteralSearch range:NSMakeRange(newLine.location, [webPage length] - newLine.location)];
	}
		
	//footer 
	[webPage appendString:@"</pre>"];
	[webPage appendString:HTML_FOOTER];
	
	return webPage;
}


- (void)openInBrowserThePath:(NSString *)aPath inNewWindow:(BOOL)openInNewWindow {
	
	// Open in a new window, explorer is special and needs a script
	// Otherwise open with script from the script.string file
	if (openInNewWindow) {
		if ([[preferences objectForKey:@"Browser"] isEqualToString:@"Explorer"]) {
			
			NSString *scriptSource = [NSString stringWithFormat:@"tell application \"Internet Explorer\"\nOpenURL \"file://%@\" toWindow 0\nend tell", aPath];
			NSAppleScript *script = [[[NSAppleScript alloc] initWithSource:scriptSource] autorelease];
			[script executeAndReturnError:nil];
		}
		else 
			[[NSWorkspace sharedWorkspace] openFile:aPath withApplication:callingApplication];
	}
	else {
		
		//Other wise open with the script in current browser
		NSString *scriptSource = [NSString stringWithFormat:[[NSBundle mainBundle] localizedStringForKey:callingApplication value:@"" table:@"scripts"], aPath];
				
		// The calling application was not a browser we know of open in a new window in the last used browser
		if ([scriptSource isEqualToString:callingApplication]) {
			[callingApplication release];
			callingApplication = [[preferences objectForKey:@"Browser"] retain];
			[self openInBrowserThePath:aPath inNewWindow:YES];
		}
		else {
			
			// Run the script
			NSAppleScript *script = [[[NSAppleScript alloc] initWithSource:scriptSource] autorelease];
			[script executeAndReturnError:nil];
			
			// Save last used browser in preference if different from current preference
			if (![callingApplication isEqualToString:[preferences objectForKey:@"Browser"]])
				[preferences setObject:callingApplication forKey:@"Browser"];
		}
	}
	
}


#pragma mark -
#pragma mark IBAction
- (IBAction)manualPage:(id)sender {
	[self showManualPage:[manTextField stringValue] inNewWindow:YES];
}


- (IBAction)openBruji:(id)sender {
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://www.bruji.com/"]];
}


- (IBAction)masterIndex:(id)sender {
	// If we were asked to index by a button, it must be from the app's UI, so we'll open in new window
	[self showIndexWithFilter:nil inNewWindow:[sender isKindOfClass:[NSButton class]]];
}


// Daniel Jalkut was kind enough to add this code
- (void) showIndexWithFilter:(NSString*)indexFilter inNewWindow:(BOOL)openInNewWindow
{	
	[self showIndexWithFilter:indexFilter inNewWindow:openInNewWindow usingCache:YES];
}


- (void) showIndexWithFilter:(NSString*)indexFilter inNewWindow:(BOOL)openInNewWindow usingCache:(BOOL)useCache
{	
	//NSLog(@"Index with filter: %@", indexFilter ? indexFilter : @"none");
	NSMutableString *webPage = [NSMutableString string];
	NSFileManager *manager = [NSFileManager defaultManager];
	
	// Figure the name for our cached index given the filter (or lack thereof)
	NSString *thisIndexCacheFilePath = [NSString stringWithFormat:@"%@/manindex-%@.html", cachesFolder, indexFilter ? indexFilter : @""];	

	// If we don't have an index cached, try to build one 
	if ((useCache == NO) || ([manager fileExistsAtPath:thisIndexCacheFilePath] == NO)) {
		// Show the "loading" page while we get things organized
		NSString *creatingIndexFile = [[NSBundle mainBundle] pathForResource:@"loading" ofType:@"html"];	
		[self openInBrowserThePath:creatingIndexFile inNewWindow:openInNewWindow];
			
		[webPage appendString:[NSString stringWithFormat:HTML_HEADER_INDEX, indexFilter ? indexFilter : @""]];
		
		NSMutableArray *manPathsToUse = [NSMutableArray array];
		NSString *nextLine;

	
		//Get all the man paths from  /usr/share/misc/man.conf
		NSString *manConfFile;
		if ([self isLeopard])
			manConfFile = [NSString stringWithContentsOfFile:@"/private/etc/man.conf"];
		else
			manConfFile = [NSString stringWithContentsOfFile:@"/usr/share/misc/man.conf"];

		NSEnumerator *linesOfFileEnum = [[manConfFile componentsSeparatedByString:@"\n"] objectEnumerator];
			
		while (nextLine = [linesOfFileEnum nextObject]) {
			if (![nextLine hasPrefix:@"#"] && ([nextLine hasPrefix:@"MANPATH "] || [nextLine hasPrefix:@"MANPATH\t"]))
				[manPathsToUse addObject:[nextLine substringFromIndex:8]];
		}
		
		//Get all the man paths from man -w in login shell 
		// By Tetsuro Kurita from the forum
		// http://homepage.mac.com/tkurita/scriptfactory/en/ 
		NSTask *listManPathTask = [[NSTask alloc] init]; 
		NSPipe *listManPathPipe = [NSPipe pipe]; 
		NSFileHandle *listManPathHandle = [listManPathPipe fileHandleForReading]; 
		[listManPathTask setStandardOutput:listManPathPipe]; 
			
		//char *login_shell = getenv("SHELL"); 
		[listManPathTask setLaunchPath:@"/bin/bash"]; 
		[listManPathTask setArguments:[NSArray arrayWithObjects:@"-lc", @"/usr/bin/man -w", nil]]; 
		[listManPathTask launch]; 
			
		NSData *dataRecieved = [listManPathHandle readDataToEndOfFile]; 
		NSString *manPathes = [[[NSString alloc] initWithData:dataRecieved encoding:NSUTF8StringEncoding] autorelease]; 
		if ([manPathes hasSuffix:@"\n"])
			manPathes = [manPathes substringToIndex:[manPathes length] - 1];
		
		//int status = [listManPathTask terminationStatus];
		[listManPathTask terminate];
		[listManPathTask release];
		
		NSEnumerator *shellPaths = [[manPathes componentsSeparatedByString:@":"] objectEnumerator];
		while (nextLine = [shellPaths nextObject]) {
			if (![manPathsToUse containsObject:nextLine])
				[manPathsToUse addObject:nextLine];
		}		
				
		int i;	
		NSEnumerator *manPagePaths = [manPathsToUse objectEnumerator];
		NSString *manDirectory;
		
		//HTML structure should be updated to not use tables
		int itemsAdded = 0;
		
		while (manDirectory = [manPagePaths nextObject]) {
			BOOL addedDirectoryHTML = NO;		
			
			for (i = 1; i < 10; i++) {
				// To continue if not all sections exist
				// Done by Nathaniel Gray n8gray [at] caltech [dot] edu
				if ([manager fileExistsAtPath:[NSString stringWithFormat:@"%@/man%d", manDirectory, i]]) {
				
					int j = 0;
				BOOL addedSectionHTML = NO;
				
				[webPage appendString:@"<table width=\"100%\"  border=\"0\">"];
				
				NSEnumerator *e = [[manager directoryContentsAtPath:[NSString stringWithFormat:@"%@/man%d", manDirectory, i]] objectEnumerator];
				NSString *currItem;
				while (currItem = [e nextObject]) {
					NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
					NSRange sections;
					if (![currItem hasPrefix:@"."] && (sections = [currItem rangeOfString:@"."]).location != NSNotFound) {
						NSString *manName = [currItem substringToIndex:sections.location];
						
						NSRange filterRange = {NSNotFound, 0};
						if (indexFilter != nil) filterRange = [manName rangeOfString:indexFilter];					
						if ((indexFilter == nil) || (filterRange.location != NSNotFound))
						{
							if (indexFilter != nil)
							{
								// Adjust manName to contain emboldened substring
								manName = [[[NSMutableString alloc] initWithString:manName] autorelease];
								[(NSMutableString*)manName replaceOccurrencesOfString:indexFilter withString:[NSString stringWithFormat:@"<strong>%@</strong>", indexFilter] options:0 range:NSMakeRange(0, [manName length])];
							}
							
							// We're showing an item, if we haven't put a directory header in yet, do it now
							if (addedDirectoryHTML == NO)
							{
								[webPage appendString:[NSString stringWithFormat:@"<p align=\"center\" class=\"blueBox\">Manual pages under %@.</p>", manDirectory]];
								addedDirectoryHTML = YES;
							}
							
							// Add section HTML if we haven't yet 
							if (addedSectionHTML == NO)
							{
								switch (i) {
									case 1:
										[webPage appendString:@"<p align=\"center\" class=\"blueBox\">General Commands</p>"];
										break;
									case 2:
										[webPage appendString:@"<p align=\"center\" class=\"blueBox\">System Calls</p>"];
										break;
									case 3:
										[webPage appendString:@"<p align=\"center\" class=\"blueBox\">Library Calls</p>"];
										break;
									case 4:
										[webPage appendString:@"<p align=\"center\" class=\"blueBox\">Kernel Interfaces</p>"];
										break;
									case 5:
										[webPage appendString:@"<p align=\"center\" class=\"blueBox\">File Formats</p>"];
										break;
									case 6:
										[webPage appendString:@"<p align=\"center\" class=\"blueBox\">Games</p>"];
										break;
									case 7:
										[webPage appendString:@"<p align=\"center\" class=\"blueBox\">Miscellaneous Information</p>"];
										break;
									case 8:
										[webPage appendString:@"<p align=\"center\" class=\"blueBox\">System Manager's Manuals</p>"];
										break;
									case 9:
										[webPage appendString:@"<p align=\"center\" class=\"blueBox\">Kernel Developers Guide</p>"];
										break;
									default:
										[webPage appendString:@"<p align=\"center\" class=\"blueBox\">Unknown</p>"];
										break;									
								}
								addedSectionHTML = YES;
							}
							
							// Add a cell for this item, and a new row if appropriate
							if (j == 0)
								[webPage appendString:@"<tr><td width=\"50%\">"];
							else
								[webPage appendString:@"<td width=\"50%\">"];
							
							[webPage appendString:[NSString stringWithFormat:@"<a href=\"man:%@\">%@(%d)</a> - ", currItem, manName, i]];
							
							NSString *manFilePath = [NSString stringWithFormat:@"%@/man%d/%@", manDirectory, i, currItem];
							
							//Unstuff if necessary
							if ([manFilePath hasSuffix:@".gz"]) {
								manFilePath = [self unzip:manFilePath];
							}
							
							NSString *manFile = [NSString stringWithContentsOfFile:manFilePath];
							
							if ([manFile hasPrefix:@".so"]) {
								NSArray *parts = [manFile componentsSeparatedByString:@"\n"];
								parts = [[parts objectAtIndex:0] componentsSeparatedByString:@" "];
								
								NSString *newLocationOfFile = [NSString stringWithFormat:@"%@/%@", manDirectory, [parts objectAtIndex:1]];
								//Unstuff if necessary
								if ([manFilePath hasSuffix:@".gz"]) {
									newLocationOfFile = [self unzip:newLocationOfFile];
								}
								
								manFile = [NSString stringWithContentsOfFile:newLocationOfFile];
							}
							
							if ((sections = [manFile rangeOfString:@".Nd"]).location != NSNotFound) {
								NSRange newLine = [manFile lineRangeForRange:NSMakeRange(sections.location, 2)];
								
								if (newLine.location != NSNotFound) {						
									NSString *description = [manFile substringWithRange:newLine];
									
									if ([description hasPrefix:@".Nd "])
										description = [description substringFromIndex:4];
									if (description)
										[webPage appendString:[self encodeForHTML:description]];
								}
							}
							else if ((sections = [manFile rangeOfString:@".SH NAME" options:NSCaseInsensitiveSearch]).location != NSNotFound || (sections = [manFile rangeOfString:@".SH \"NAME\"" options:NSCaseInsensitiveSearch]).location != NSNotFound) {
								
								// move forward to next line
								NSRange newLine = [manFile lineRangeForRange:NSMakeRange(sections.location + 15, 2)]; 
								
								NSString *description = [manFile substringWithRange:newLine];
								unsigned int dashLocation = [description rangeOfString:@"-"].location;
								
								// Move forward to next line for multi-line descriptions
								while (dashLocation == NSNotFound) {
									newLine = [manFile lineRangeForRange:NSMakeRange(newLine.location + newLine.length + 2, 1)]; 
									description = [manFile substringWithRange:newLine];
									if ([description hasPrefix:@"."]) //already not description
										break;
									dashLocation = [description rangeOfString:@"-"].location;
								}
								
								if (dashLocation != NSNotFound) {
									description = [description substringFromIndex:dashLocation +2];
									if (description)
										[webPage appendString:[self encodeForHTML:description]];		
								}
							}							
							
														
							if (j == 0) {
								[webPage appendString:@"</td>"];
								j++;
							}
							else {
								j = 0;
								[webPage appendString:@"</td></tr>"];
							}
							
							itemsAdded += 1;
						}												
					}
					//else {
					//	[webPage appendString:@"Unknown File"];
					//}		
					[pool release];
				}
				[webPage appendString:@"</table>"];
				}
			}		
		}
		
		// IF we didn't add any results, then we let the user know there were no matches
		if (itemsAdded == 0)
		{
			[webPage appendString:[NSString stringWithFormat:@"<p align=\"center\" class=\"blueBox\">Sorry, no man page names contain the string \"%@\"</p>", indexFilter]];
		}
		
		[webPage appendString:HTML_FOOTER];

		// Cache this index
		[webPage writeToFile:thisIndexCacheFilePath atomically:NO];
	}
	
	// Try to open whatever we've got
	[self openInBrowserThePath:thisIndexCacheFilePath inNewWindow:openInNewWindow];
	[NSApp terminate:self];	
}


#pragma mark -
#pragma mark NSTasks
- (NSString *)manualPageFor:(NSString *)manualPage section:(NSString *)section {
	
	NSTask *findPathTask = [[[NSTask alloc] init] autorelease];
	NSPipe *findPathPipe = [NSPipe pipe];
	NSFileHandle *findPathHandle = [findPathPipe fileHandleForReading];
	[findPathTask setStandardOutput:findPathPipe];
	// Changes by Tetsuro Kurita
	// http://homepage.mac.com/tkurita/scriptfactory/en/ 
	//[findPathTask setLaunchPath:@"/usr/bin/man"];
	//char *login_shell = getenv("SHELL"); 
	[findPathTask setLaunchPath:@"/bin/bash"]; 
	//-M use the -M option with the paths listed
	if (section)
		 [findPathTask setArguments:[NSArray arrayWithObjects:@"-lc", @"/usr/bin/man -w $0 $1", section, manualPage, nil]]; 
		//[findPathTask setArguments:[NSArray arrayWithObjects:@"-w", section, manualPage, nil]];
	else
		[findPathTask setArguments:[NSArray arrayWithObjects:@"-lc", @"/usr/bin/man -w $0", manualPage, nil]]; 
		//[findPathTask setArguments:[NSArray arrayWithObjects:@"-w", manualPage, nil]];

	[findPathTask launch];
	
	/*
	NSString *findManPageCommand;
	if (section)
		findManPageCommand = [NSString stringWithFormat:@"/usr/bin/man -w %@ %@", section, manualPage];
	else
		findManPageCommand = [NSString stringWithFormat:@"/usr/bin/man -w %@", manualPage];
	[findPathTask setArguments:[NSArray arrayWithObjects:@"-lc", findManPageCommand, nil]]; 
	 */
	
	NSString *pathToManual = nil;
	NSData *dataRecieved = [findPathHandle readDataToEndOfFile];
	if ([dataRecieved length]) {
		pathToManual = [[[NSString alloc] initWithData:dataRecieved encoding:NSASCIIStringEncoding] autorelease];
		
		//remove EOF
		pathToManual = [pathToManual substringToIndex:[pathToManual length] -1];
		
		// by billyw forum
		//To get just the last line of the output in case fortune or other programs that output data during login are installed
		NSArray *cmdLines = [pathToManual componentsSeparatedByString: @"\n"];
		pathToManual = [cmdLines lastObject];
		
		//make sure it starts with a / otherwise make nil
		if (![pathToManual hasPrefix:@"/"])
			pathToManual = nil;
	}
	[findPathHandle closeFile]; //FZiegler
	//[findPathTask terminate];
	//[findPathTask release];

	//	Try lowercase string if not already lowercase
	// try removing any period extensions
	if (pathToManual == nil) {
		int aLocation;
		if ((aLocation = [manualPage rangeOfString:@"." options:NSBackwardsSearch].location) != NSNotFound) {
			manualPage = [manualPage substringToIndex:aLocation];
			return [self manualPageFor:manualPage section:section];
		}
		
		NSString *lowerCaseManualPage = [manualPage lowercaseString];
		if (![lowerCaseManualPage isEqualToString:manualPage])
			return [self manualPageFor:lowerCaseManualPage section:section];
	}
	
	//unzip man path if necessary into temp
	if ([pathToManual hasSuffix:@".gz"]) {
		pathToManual = [self unzip:pathToManual];
	}
	
	//If the path was not found recursively remove path extensions see if the path can be found
	if (pathToManual == nil && ![[manualPage pathExtension] isEqualToString:@""]) {
		pathToManual = [self manualPageFor:[manualPage stringByDeletingPathExtension] section:section];
	}
	
	return pathToManual;
}


//bzip unzip
//usr/bin/bzip2 -c -d  .bz2
///usr/bin/zcat .z
// Better if done with the zlib library in order to avoid opening many threads when building the index  
//#include "/usr/include/zlib.h"
- (NSString *)unzip:(NSString *)aPath {
	/*
	gzFile fileOpened = gzopen([aPath UTF8String], "rb");
	
	if( file_exists($mygzfile) {
	   $zd = gzopen($mygzfile);
	   char buffer;
	   while(gzread($zd, , 10000)) != EOF ) {
	   $bytes += strlen($zdcontents);
	   }
	   gzclose($zd);
	   echo "The uncompressed file has $bytes bytes in it\n";
	   }
	 
	 
	 Byte*        uncompressedBytes;
	 uLong        len, comprLen;
	 int            err;
	 int            memFile, bytesWritten;
	 gzFile        gzmemFile;
	 
	 //    uncompressedBytes and len have been initialized (I've check in the 
	 debugger)
	 
	 memFile = shm_open("/memfile", O_RDWR | O_CREAT, 0777);
	 
	 gzmemFile = gzdopen(memFile, "wb");
	 //    if I write to "tmpFile" (instead of an in-memory file) then 
	 everything works
	 //    gzmemFile = gzopen("tmpFile", "wb");
	 bytesWritten = gzwrite(gzmemFile, uncompressedBytes, len);
	 
	 err = gzclose(gzmemFile);
	 
	 //    Do some fun stuff
	 
	 shm_unlink("/memfile");
	   
	gzclose(fileOpened);
	*/
	NSTask *gunzipTask = [[NSTask alloc] init];
	NSPipe *gunzipPipe = [NSPipe pipe];
	NSFileHandle *gunzipHandle = [gunzipPipe fileHandleForReading];
	[gunzipTask setStandardOutput:gunzipPipe];
	[gunzipTask setLaunchPath:@"/usr/bin/gunzip"];
	[gunzipTask setArguments:[NSArray arrayWithObjects:@"-c", aPath, nil]];
	//[gunzipTask waitUntilExit];
	[gunzipTask launch];
	
	NSString *unzippedPath = nil;
	NSData *dataRecieved = [gunzipHandle readDataToEndOfFile]; 
	if ([dataRecieved length]) {
		NSString *unzippedString = [[[NSString alloc] initWithData:dataRecieved encoding:NSASCIIStringEncoding] autorelease];
		
		//remove EOF
		unzippedString = [unzippedString substringToIndex:[unzippedString length] -1];
		
		unzippedPath = [NSString stringWithFormat:@"%@/%@.txt", NSTemporaryDirectory(), [[aPath lastPathComponent] stringByDeletingPathExtension]];
		[unzippedString writeToFile:unzippedPath atomically:NO];
	}
	
	[gunzipHandle closeFile];  //FZiegler
	[gunzipTask terminate];
	[gunzipTask release];
	return unzippedPath;
}

// /usr/bin/groff -Wall -mtty-char -Tascii -mandoc -c /Users/fa/Desktop/mysql.1 
- (NSString *)asciiFormatForManualPath:(NSString *)manualPagePath  {
	NSString *asciiFormatedOutput = nil;
	
	 // We should pass the string through tbl in order to handle tables

	//pass to tbl
	// Get the output for the man path formated by groff for ascii
	NSTask *tblTask = [[[NSTask alloc] init] autorelease];
	NSPipe *tblPipe = [NSPipe pipe];
	NSFileHandle *tblHandle = [tblPipe fileHandleForReading];
	[tblTask setLaunchPath:@"/usr/bin/tbl"];
	[tblTask setStandardOutput:tblPipe];
	[tblTask setArguments:[NSArray arrayWithObjects:manualPagePath, nil]];
	[tblTask launch];
	
	NSData *dataRecieved = [tblHandle readDataToEndOfFile];
	if ([dataRecieved length]) {
		asciiFormatedOutput = [[[NSString alloc] initWithData:dataRecieved encoding:NSASCIIStringEncoding] autorelease];
	}
	
	// NSLog(@"%@", asciiFormatedOutput);
	[tblHandle closeFile];  //FZiegler
	
	//pass to groff
	NSString *tempLocation = [NSTemporaryDirectory() stringByAppendingPathComponent:@"BwanaTemp.txt"];
	// NSLog(@"%@", tempLocation);
	[asciiFormatedOutput writeToFile:tempLocation atomically:NO];
	
	 // Get the output for the man path formated by groff for ascii
	 NSTask *groffTask = [[[NSTask alloc] init] autorelease];
	 NSPipe *groffPipe = [NSPipe pipe];
	 NSFileHandle *groffHandle = [groffPipe fileHandleForReading];
	 [groffTask setLaunchPath:@"/usr/bin/groff"];
	 [groffTask setStandardOutput:groffPipe];
	 [groffTask setArguments:[NSArray arrayWithObjects:@"-Wall", @"-mandoc", @"-Tascii", tempLocation, nil]];
	 [groffTask launch];
	 
	 dataRecieved = [groffHandle readDataToEndOfFile];
	 if ([dataRecieved length]) {
		asciiFormatedOutput = [[[NSString alloc] initWithData:dataRecieved encoding:NSASCIIStringEncoding] autorelease];
	 }
	 
	 [groffHandle closeFile];  //FZiegler
	 
	/*
	// Get the output for the man path formated by groff for ascii
	NSTask *groffTask = [[[NSTask alloc] init] autorelease];
	NSPipe *groffPipe = [NSPipe pipe];
	NSFileHandle *groffHandle = [groffPipe fileHandleForReading];
	[groffTask setLaunchPath:@"/usr/bin/groff"];
	[groffTask setStandardOutput:groffPipe];
	[groffTask setArguments:[NSArray arrayWithObjects:@"-mandoc", @"-Tascii", manualPagePath, nil]];
	[groffTask launch];
	
	NSData *dataRecieved = [groffHandle readDataToEndOfFile];
	if ([dataRecieved length]) {
		asciiFormatedOutput = [[[NSString alloc] initWithData:dataRecieved encoding:NSASCIIStringEncoding] autorelease];
	}
	
	[groffHandle closeFile];  //FZiegler
	 */
	 
	return asciiFormatedOutput;
}


- (BOOL)isLeopard {
	if (osVersion == 0) {
		Gestalt(gestaltSystemVersion,&osVersion);
		if (osVersion >= 0x00001050)
			isLeopard = YES;
	}
	
	return isLeopard;
}

#pragma mark -
#pragma mark Helpers
- (NSMutableString *)encodeForHTML:(NSString *)aString {
	if (aString == nil)
		return nil;
	
	NSMutableString *stringToEncode = [NSMutableString stringWithString:aString];
	
	unsigned int i, count = [stringToEncode length];
	for (i =0; i < count; i++) {
		//as we replacce working repeat it grows
		unichar character = [stringToEncode characterAtIndex:i];
		
		if (character == '&') {
			[stringToEncode replaceCharactersInRange:NSMakeRange(i,1) withString:@"&amp;"];
			count = [stringToEncode length];
			i += 4; //Move forward the amp;
		}
		else if (character == '<') {
			[stringToEncode replaceCharactersInRange:NSMakeRange(i,1) withString:@"&lt;"];
			count = [stringToEncode length];
			i += 3; //Move forward the lt;
		}
		else if (character == '>') {
			[stringToEncode replaceCharactersInRange:NSMakeRange(i,1) withString:@"&gt;"];
			count = [stringToEncode length];
			i += 3; //Move forward the lt;
		}
	}
	
	return stringToEncode;
}


#pragma mark NSWindow Delegate
- (BOOL)windowShouldClose:(id)sender {
	[NSApp terminate:self];
	return YES;
}

@end


#pragma mark -
@implementation MyController (ApplicationNotifications)


- (void)applicationWillFinishLaunching:(NSNotification *)aNotification {
	
	//create cache folder if it doesn't exist
	cachesFolder = [[@"~/Library/Caches/Bwana" stringByExpandingTildeInPath] retain];
	if (![[NSFileManager defaultManager] fileExistsAtPath:cachesFolder])
		[[NSFileManager defaultManager] createDirectoryAtPath:cachesFolder attributes:nil];
	
	//Register for the URL get event
	[[NSAppleEventManager sharedAppleEventManager] setEventHandler:self andSelector:@selector(handleAppleEvent:withReplyEvent:) forEventClass:kInternetEventClass andEventID:kAEGetURL];	
}


- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	// The program was opened with a double clik not by the system, show the main window
	if (!dontDisplayWindow) {
		callingApplication = [@"Safari" retain];
		
		[versionTextField setStringValue:[NSString stringWithFormat:@"Version: %@",[[[NSBundle bundleForClass:[self class]] infoDictionary] objectForKey:@"CFBundleVersion"] ]];
		[[versionTextField window] makeKeyAndOrderFront:self];	
	}
}


- (BOOL)applicationShouldHandleReopen:(NSApplication *)theApplication hasVisibleWindows:(BOOL)flag {
	if (!flag) {
		[versionTextField setStringValue:[NSString stringWithFormat:@"Version: %@",[[[NSBundle bundleForClass:[self class]] infoDictionary] objectForKey:@"CFBundleVersion"] ]];
		[[versionTextField window] makeKeyAndOrderFront:self];		
	}
	
	return NO;
}


@end
