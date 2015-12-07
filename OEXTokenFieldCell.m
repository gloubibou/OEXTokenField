//
//  OEXTokenFieldCell.m
//  OEXTokenField
//
//  Created by Nicolas BACHSCHMIDT on 16/03/2013.
//  Copyright (c) 2013 Octiplex. All rights reserved.
//

#import "OEXTokenFieldCell.h"
#import "OEXTokenTextStorage.h"

#import <objc/runtime.h>

static int kOEXTokenFieldCellRepresentedObjectKey;

@interface OEXTokenFieldCell () <NSTextStorageDelegate, OEXTokenTextStorageDelegate>
@end

//@interface NSTokenFieldCell (Private)
//
//- (id)_representedObjectsForString:(id)arg1 andAttributedString:(id)arg2 range:(struct _NSRange)arg3;
//- (BOOL)tokenTextView:(id)arg1 writeSelectionToPasteboard:(id)arg2 type:(id)arg3;
//
//@end

@implementation OEXTokenFieldCell
{
    NSTokenFieldCell    *_tokenCell;
    NSArray             *_objects;
}

@dynamic delegate;

#pragma mark - Attributed String Value

- (NSAttributedString *)attributedStringValue
{
    // The token cells are drawn using text attachments
    // Replace attachment cells before displaying the string
    
    NSAttributedString *attrString = super.attributedStringValue;
    NSRange range = NSMakeRange(0, attrString.length);
    [attrString enumerateAttribute:NSAttachmentAttributeName inRange:range options:0 usingBlock:^(NSTextAttachment *attachment, NSRange range, BOOL *stop) {
        if ( attachment ) {
            [self updateTokenAttachment:attachment forAttributedString:[attrString attributedSubstringFromRange:range]];
        }
    }];
    return attrString;
}

- (void)setAttributedStringValue:(NSAttributedString *)attrString
{
    // The default implementation of setAttributedString: cannot handle attachments with replaced cells
    // Transform the attributed string to array of represented objects
    
    NSMutableArray *objects = [NSMutableArray new];
    NSRange range = NSMakeRange(0, attrString.length);
    [attrString enumerateAttribute:NSAttachmentAttributeName inRange:range options:0 usingBlock:^(id attachment, NSRange range, BOOL *stop) {
        id representedObject = [self representedObjectWithAttachment:attachment attributedString:[attrString attributedSubstringFromRange:range]];
        [objects addObject:representedObject];
    }];
    
    [self setObjectValue:objects];
}

#pragma mark - Field Editor

- (NSText *)setUpFieldEditorAttributes:(NSText *)textObj
{
    // Replace the text storage of the text view so we can replace attachment cells on the fly
    
    NSTextView *textView = (NSTextView *) [super setUpFieldEditorAttributes:textObj];
    
    if ( [textView isKindOfClass:[NSTextView class]] )
    {
        NSLayoutManager *layoutManager = textView.textContainer.layoutManager;
        OEXTokenTextStorage *textStorage = (OEXTokenTextStorage *) layoutManager.textStorage;
        
        if ( ! [textStorage isKindOfClass:[OEXTokenTextStorage class]] ) {
            textStorage = [[OEXTokenTextStorage alloc] initWithAttributedString:textStorage];
            [layoutManager replaceTextStorage:textStorage];
        }
        
        textStorage.delegate = self;
    }
    
    return textView;
}

- (void)endEditing:(NSText *)textObj
{
    NSTextView *textView = (NSTextView *) textObj;
    if ( [textView isKindOfClass:[NSTextView class]] )
    {
        OEXTokenTextStorage *textStorage = (OEXTokenTextStorage *) textView.textContainer.layoutManager.textStorage;
        if ( [textStorage isKindOfClass:[OEXTokenTextStorage class]] ) {
            textStorage.delegate = nil;
        }
    }
    [super endEditing:textObj];
}

#pragma mark - Token Replacement

- (void)updateTokenAttachment:(NSTextAttachment *)attachment forAttributedString:(NSAttributedString *)attrString
{
    // If the represented object in set, we've already updated the attachment
    if ( objc_getAssociatedObject(attachment, &kOEXTokenFieldCellRepresentedObjectKey) )
        return;
    
    id representedObject = [self representedObjectWithAttachment:attachment attributedString:attrString];
    objc_setAssociatedObject(attachment, &kOEXTokenFieldCellRepresentedObjectKey, representedObject, OBJC_ASSOCIATION_RETAIN);
    
    // Replace the attachment's cell
    id <NSTextAttachmentCell> cell = attachment.attachmentCell;
    cell = [self attachmentCellForRepresentedObject:representedObject] ?: cell;
    [cell setAttachment:attachment];
    [attachment setAttachmentCell:cell];
}

- (NSTextAttachmentCell *)attachmentCellForRepresentedObject:(id)representedObject;
{
    NSTextAttachmentCell *cell = nil;
    if ( [self.delegate respondsToSelector:@selector(tokenFieldCell:attachmentCellForRepresentedObject:)] ) {
        cell = [self.delegate tokenFieldCell:self attachmentCellForRepresentedObject:representedObject];
    }
    
    cell.font = self.font;
    return cell;
}

- (id)representedObjectWithAttachment:(NSTextAttachment *)attachment attributedString:(NSAttributedString *)attrString
{
    // If the attachment was updated, we just need to access the associated object
    if ( attachment && objc_getAssociatedObject(attachment, &kOEXTokenFieldCellRepresentedObjectKey) )
        return objc_getAssociatedObject(attachment, &kOEXTokenFieldCellRepresentedObjectKey);
    
    // This attributed string was generated by NSTokenField
    // As we don't want to rely on private APIs (NSTokenAttachment/NSTokenAttachmentCell), let's just use a NSTokenFieldCell to do the job
    
    if ( ! _tokenCell )
        _tokenCell = [NSTokenFieldCell new];
    
    _tokenCell.attributedStringValue = attrString;
    NSArray *objectValue = _tokenCell.objectValue;
    return objectValue.count ? objectValue[0] : attrString.string;
}

#pragma mark - OEXTokenTextStorageDelegate

- (void)tokenTextStorage:(OEXTokenTextStorage *)textStorage updateTokenAttachment:(NSTextAttachment *)attachment forRange:(NSRange)range
{
    [self updateTokenAttachment:attachment forAttributedString:[textStorage attributedSubstringFromRange:range]];
}

#pragma mark - Pasteboard

- (BOOL)tokenTextView:(NSTextView *)tokenView writeSelectionToPasteboard:(NSPasteboard *)pasteboard type:(NSString *)type
{
	if ([tokenView respondsToSelector:@selector(selectedRanges)]) {
		NSAttributedString *attrString = [tokenView attributedString];
		NSMutableArray *selectedObjects = [NSMutableArray new];

		for (NSValue *rangeValue in [(id)tokenView selectedRanges]) {
			NSRange range = rangeValue.rangeValue;
			NSRange currentRange = range;

			do {
				NSRange effectiveRange = NSMakeRange(0, 0);
				NSRange searchRange = NSMakeRange(currentRange.location, MIN(currentRange.length, attrString.length - currentRange.location));

				id attachment = [attrString attribute:NSAttachmentAttributeName atIndex:currentRange.location effectiveRange:&effectiveRange];

				if (attachment != nil) {
					NSAttributedString *subStr = [attrString attributedSubstringFromRange:effectiveRange];
					id representedObject = [self representedObjectWithAttachment:attachment attributedString:subStr];

					if (representedObject != nil) {
						[selectedObjects addObject:representedObject];
					}
				}
				else {
					NSDictionary *attributes = [attrString attributesAtIndex:currentRange.location
													   longestEffectiveRange:&effectiveRange
																	 inRange:searchRange];

					if (attributes != nil) {
						id attachment = [attributes objectForKey:NSAttachmentAttributeName];
						NSAttributedString *subStr = [attrString attributedSubstringFromRange:effectiveRange];

						if (attachment != nil) {
							id representedObject = [self representedObjectWithAttachment:attachment attributedString:subStr];

							if (representedObject != nil) {
								[selectedObjects addObject:representedObject];
							}
						}
						else {
							NSString *string = [subStr string];

							if (string != nil) {
								[selectedObjects addObject:string];
							}
						}
					}
				}
				
				currentRange.location += effectiveRange.length;
				currentRange.length -= effectiveRange.length;
			}
			while (currentRange.location < (range.location + range.length));
		}

		if ([pasteboard writeObjects:selectedObjects]) {
			return YES;
		}
	}

	return NO;
}

@end
