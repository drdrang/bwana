//
//  MyController.h

// Conor Dearden, Daniel Jalkut, Mark Johnston, FZiegler

/*
Bwana is free software; you can redistribute it and/or modify
it under the terms of the The MIT License. Bwana's code is messy and scarry at times, but that is the life of code that was intended for personal use – read on at your own risk.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

#import <Cocoa/Cocoa.h>


@interface MyController : NSObject {
	
	IBOutlet NSTextField *manTextField;
	IBOutlet NSTextField *versionTextField;
	
	BOOL dontDisplayWindow, isLeopard;
	SInt32 osVersion;
	NSString *callingApplication, *cachesFolder, *manPathsToSearch;

}
- (IBAction)manualPage:(id)sender;
- (IBAction)openBruji:(id)sender;
- (IBAction)masterIndex:(id)sender;

@end
