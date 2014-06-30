/**
 * @author Michael Descy
 * @copyright 2014 Michael Descy
 * @discussion Dual-licensed under the GNU General Public License and the MIT License
 *
 *
 *
 * @license GNU General Public License http://www.gnu.org/licenses/gpl.html
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 *
 *
 *
 * @license The MIT License (MIT)
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#import "TTMDocument.h"
#import "TTMTask.h"
#import "TTMDateUtility.h"
#import "TTMFilterPredicates.h"
#import "TTMFieldEditor.h"
#import "RegExCategories.h"

@implementation TTMDocument

#pragma mark - Instance Variables and Blocks

static NSString * const RelativeDueDatePattern = @"(?<=due:)\\S*";

// The following code blocks are called on all selected tasks in the table/arrayController.
TaskChangeBlock _toggleTaskCompletion = ^(id task, NSUInteger idx, BOOL *stop) {
    [(TTMTask*)task toggleCompletionStatus];
};
TaskChangeBlock _increaseTaskPriority = ^(id task, NSUInteger idx, BOOL *stop) {
    [(TTMTask*)task increasePriority];
};
TaskChangeBlock _decreaseTaskPriority = ^(id task, NSUInteger idx, BOOL *stop) {
    [(TTMTask*)task decreasePriority];
};
TaskChangeBlock _removeTaskPriority   = ^(id task, NSUInteger idx, BOOL *stop) {
    [(TTMTask*)task removePriority];
};
TaskChangeBlock _increaseDueDateByOneDay   = ^(id task, NSUInteger idx, BOOL *stop) {
    [(TTMTask*)task postponeTask:1];
};
TaskChangeBlock _decreaseDueDateByOneDay   = ^(id task, NSUInteger idx, BOOL *stop) {
    [(TTMTask*)task postponeTask:-1];
};
TaskChangeBlock _removeDueDate   = ^(id task, NSUInteger idx, BOOL *stop) {
    [(TTMTask*)task removeDueDate];
};

#pragma mark - init Methods

- (id)init
{
    self = [super init];
    if (self) {
        [[self undoManager] disableUndoRegistration];
        _taskList = [[NSMutableArray alloc] init];
        _arrayController = [[NSArrayController alloc] initWithContent:_taskList];
        _preferredLineEnding = @"\n";
        _usesWindowsLineEndings = NO;
        [[self undoManager] enableUndoRegistration];
    }
    return self;
}

- (void)awakeFromNib {
    // Enable autosaving.
    [[NSDocumentController sharedDocumentController] setAutosavingDelay:1.0];
    
    // Set custom field editor.
    
    // Set arrayController sort type.
    TTMTaskListSortType taskListSortType =
        [[NSUserDefaults standardUserDefaults] integerForKey:@"taskListSortType"];
    [self sortTaskList:taskListSortType];

    // Load active filter predicate.
    self.activeFilterPredicate = [TTMFilterPredicates getActiveFilterPredicate];
    
    // Set up drag and drop for tableView.
    [self.tableView setDraggingSourceOperationMask:NSDragOperationEvery forLocal:NO];
    [self.tableView registerForDraggedTypes:[NSArray arrayWithObject:NSStringPboardType]];
    
    // Set up font selection for tableView.
    self.usingUserFont = [[NSUserDefaults standardUserDefaults] boolForKey:@"useUserFont"];
    if (self.usingUserFont) {
        self.userFont = [NSFont userFontOfSize:0.0];
        [self.rawTextCell setFont:self.userFont];
    }
}

- (NSString *)windowNibName {
    return @"TTMDocument";
}

- (void)windowControllerDidLoadNib:(NSWindowController *)aController {
    [super windowControllerDidLoadNib:aController];
    // Add any code here that needs to be executed once the windowController
    // has loaded the document's window.
}

- (id)windowWillReturnFieldEditor:(NSWindow *)sender toObject:(id)client {
    if (!self.customFieldEditor) {
        self.customFieldEditor = [[TTMFieldEditor alloc] init];
    }
    [self.customFieldEditor setFieldEditor:YES];
    self.customFieldEditor.projectsArray = self.projectsArray;
    self.customFieldEditor.contextsArray = self.contextsArray;
    return self.customFieldEditor;
}

#pragma mark - File Loading and Saving Methods

+ (BOOL)autosavesInPlace {
    return YES;
}

- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError {
    // Prepare file contents to save.
    NSMutableString *fileData = [[NSMutableString alloc] init];
    for (int i = 0; i < [self.taskList count]; i++) {
        if ([[self.taskList objectAtIndex:i] isKindOfClass:[TTMTask class]]) {
            NSString *line = [[self.taskList objectAtIndex:i] rawText];
            // Append the string to fileData if it is not null.
            // Appending a null causes an exception.
            if (line) {
                [fileData appendString:line];
                [fileData appendString:self.preferredLineEnding];
            }
        }
    }
    return [fileData dataUsingEncoding:NSUTF8StringEncoding];
}

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)outError {
    // Read file contents.
    NSString *fileContents = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!fileContents) {
        if (outError != nil) {
            *outError = [NSError errorWithDomain:NSCocoaErrorDomain
                                            code:NSFileReadUnknownError
                                        userInfo:nil];
        }
        return NO;
    }

    // Check the line endings in the file, and remember if Windows line endings ("\r\n") are used.
    self.usesWindowsLineEndings = ([fileContents rangeOfString:@"\r\n"].location != NSNotFound);
    self.preferredLineEnding = (self.usesWindowsLineEndings) ? @"\r\n" : @"\n";
    
    // Split contents of file into an array of strings.
    // Note: A file with Windows line endings ("\r\n") may also have Unix line endings ("\n").
    // This can happen if a text file is created on Windows, then is edited on the Mac
    // (in TextEdit, for example).
    // Because inconsistent line endings can exist, for files with Windows line endings,
    // we remove the carriage return character prior to splitting the file contents into
    // an array of strings.
    NSArray *rawTextStrings = (self.usesWindowsLineEndings) ?
        [[fileContents stringByReplacingOccurrencesOfString:@"\r" withString:@""] componentsSeparatedByString:@"\n"] :
        [fileContents componentsSeparatedByString:@"\n"];

    // Refresh the arrayController and tableView
    [self addTasksFromArray:rawTextStrings removeAllTasksFirst:YES];
    
    [self updateProjectsAndContextsArrays];

    // Clear the document modified flag.
    [self updateChangeCount:NSChangeCleared];
    
    return YES;
}

- (IBAction)reloadFile:(id)sender {
    // Save the current filter number.
    NSUInteger filterNumber = self.activeFilterPredicateNumber;
    
    // Remove the current filter.
    [self removeTaskListFilter:self];
    
    // Reload the file.
    NSError *error;
    [self readFromURL:[self fileURL] ofType:@"TTMDocument" error:&error];

    // Refresh the task list.
    [self refreshTaskListWithSave:NO];
    
    // Re-apply the filter active before the file was reloaded.
    [self changeActiveFilterPredicateToPreset:filterNumber];
}

#pragma mark - Add/Remove Task Methods

- (TTMTask*)createWorkingTaskWithRawText:(NSString*)rawText withTaskId:(NSUInteger)newTaskId {
    // Convert natural-language due dates, such as "due:today" and "due:tomorrow", to YYYY-MM-DD.
    NSString *relativeDueDateText = [rawText firstMatch:RX(RelativeDueDatePattern)];
    NSString *relativeDueDateReplacementText =
        [TTMDateUtility dateStringFromNaturalLanguageString:relativeDueDateText];
    if (relativeDueDateReplacementText != nil) {
        rawText = [rawText replace:RX(RelativeDueDatePattern)
                              with:relativeDueDateReplacementText];
    }
    
    // Optionally prepend the creation date and create the task.
    BOOL prependDate = [[NSUserDefaults standardUserDefaults] boolForKey:@"prependDateOnNewTasks"];
    TTMTask *workingTask = (prependDate) ?
        [[self.arrayController newObject] initWithRawText:rawText
                                               withTaskId:newTaskId
                                        withPrependedDate:[TTMDateUtility today]] :
        [[self.arrayController newObject] initWithRawText:rawText withTaskId:newTaskId];
    return workingTask;
}

- (IBAction)moveFocusToNewTaskTextField:(id)sender {
    [self.textField becomeFirstResponder];
}

- (void)removeAllTasks {
    if ([[self.arrayController arrangedObjects] count] > 0) {
        NSRange range = NSMakeRange(0, [[self.arrayController arrangedObjects] count]);
        [self.arrayController
         removeObjectsAtArrangedObjectIndexes:[NSIndexSet indexSetWithIndexesInRange:range]];
    }
}

- (void)addTasksFromArray:(NSArray*)rawTextStrings removeAllTasksFirst:(BOOL)removeAllTasksFirst {
    if (removeAllTasksFirst) {
        [self removeAllTasks];
    }
    
    NSUInteger newTaskId = (self.arrayController == nil) ?
                            [self.taskList count] :
                            [[self.arrayController arrangedObjects] count];
    for (NSString *rawTextString in rawTextStrings) {
        if ([rawTextString length] > 0) {
            if (removeAllTasksFirst) {
                TTMTask *newTask = [[TTMTask alloc]
                                    initWithRawText:(NSString*)rawTextString
                                    withTaskId:newTaskId++];
                [self.arrayController addObject:newTask];
            } else {
                [self.arrayController
                 addObject:[self createWorkingTaskWithRawText:(NSString*)rawTextString
                                                       withTaskId:newTaskId++]];
            }
        }
    }
}

- (IBAction)addNewTask:(id)sender {
    NSString *newTaskText = [self.textField stringValue];
    
    // Reject zero-length input.
    if ([newTaskText length] == 0) {
        return;
    }
    
    NSUInteger newTaskId = [[self.arrayController arrangedObjects] count];
    [self.arrayController addObject:[self createWorkingTaskWithRawText:newTaskText
                                                            withTaskId:newTaskId]];
    [self reapplyActiveFilterPredicate];
    [self refreshTaskListWithSave:YES];
    [self.textField setStringValue:@""];
    
    // Optionally move focus to the task list depending on the user setting.
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"moveToTaskListAfterTaskCreation"]) {
        [self tabFromTextFieldToTaskList];
    }
}

- (void)tabFromTextFieldToTaskList {
    // Simulate a tab press.
    unichar keyChar = 9;
    NSString *keyDownString = [NSString stringWithCharacters:&keyChar length:1];
    NSPoint point = {0, 0};
    NSEvent *newEvent =[NSEvent keyEventWithType:NSKeyDown
                                        location:point
                                   modifierFlags:0
                                       timestamp:[NSDate timeIntervalSinceReferenceDate]
                                    windowNumber:self.windowForSheet.windowNumber
                                         context:nil
                                      characters:keyDownString
                     charactersIgnoringModifiers:keyDownString
                                       isARepeat:NO
                                         keyCode:keyChar];
    [NSApp postEvent:newEvent atStart:YES];
}

- (void)addNewTasksFromClipboard:(id)sender {
    [self addNewTasksFromPasteBoard:[NSPasteboard generalPasteboard]];
}

- (void)addNewTasksFromDragAndDrop:(id)sender {
    [self addNewTasksFromPasteBoard:[sender draggingPasteboard]];
}

- (void)addNewTasksFromPasteBoard:(NSPasteboard*)pasteboard {
    NSString *pasteboardText = [pasteboard stringForType:NSPasteboardTypeString];
    if ([pasteboardText length] == 0) {
        return;
    }
    
    NSArray *rawTextStrings = [pasteboardText
                               componentsSeparatedByCharactersInSet:
                               [NSCharacterSet newlineCharacterSet]];
    [self addTasksFromArray:rawTextStrings removeAllTasksFirst:NO];
    [self refreshTaskListWithSave:YES];
}

#pragma mark - Update Task Methods

- (void)refreshTaskListWithSave:(BOOL)saveToFile {
    // Optionally save the file.
    if (saveToFile) {
        [self updateChangeCount:NSChangeDone];
    }
    // Update the lists of projects and contexts.
    [self updateProjectsAndContextsArrays];
    // Re-sort the table.
    [self.arrayController rearrangeObjects];
    // Reload table.
    [self.tableView reloadData];
}

- (IBAction)updateSelectedTask:(id)sender {
    // cancel if multiple rows are selected
    if ([[self.tableView selectedRowIndexes] count]!=1) {
        return;
    }
    
    [self.tableView editColumn:0 row:[self.tableView selectedRow] withEvent:nil select:YES];
}

- (void)forEachSelectedTaskExecuteBlock:(TaskChangeBlock)block {
    [[self.arrayController arrangedObjects]
     enumerateObjectsAtIndexes:[self.arrayController selectionIndexes]
                       options:0
                    usingBlock:block];
    [self refreshTaskListWithSave:YES];
}

- (IBAction)toggleTaskCompletion:(id)sender {
    [self forEachSelectedTaskExecuteBlock:_toggleTaskCompletion];
    if ([[NSUserDefaults standardUserDefaults] integerForKey:@"archiveTasksUponCompletion"]) {
        [self archiveCompletedTasks:self];
    }
}

- (IBAction)deleteSelectedTasks:(id)sender {
    NSAlert *deletePrompt =
    [NSAlert alertWithMessageText:@"Delete"
                    defaultButton:@"OK"
                  alternateButton:@"Cancel"
                      otherButton:nil
        informativeTextWithFormat:@"Are you sure you want to delete all selected tasks?"];
    [deletePrompt beginSheetModalForWindow:self.windowForSheet
                         completionHandler:^(NSModalResponse returnCode) {
                             if (returnCode == NSAlertDefaultReturn) {
                                 [self.arrayController
                                  removeObjectsAtArrangedObjectIndexes:[self.tableView
                                                                        selectedRowIndexes]];
                                 [self refreshTaskListWithSave:YES];
                             }
                         }];
}

- (IBAction)appendText:(id)sender {
    NSAlert *alert = [NSAlert alertWithMessageText:@"Append Text"
                                     defaultButton:@"OK"
                                   alternateButton:@"Cancel"
                                       otherButton:nil
                         informativeTextWithFormat:@"Text to append to each selected task:"];
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 295, 24)];
    [input setStringValue:@""];
    [alert setAccessoryView:input];
    
    // Define the completion handler for the modal sheet.
    void (^appendTextHandler)(NSModalResponse returnCode) = ^(NSModalResponse returnCode) {
        if (returnCode != NSAlertDefaultReturn || [[input stringValue] length] == 0) {
            return;
        }
        
        TaskChangeBlock appendTextTaskBlock = ^(id task, NSUInteger idx, BOOL *stop) {
            NSString *newRawText = [[task rawText]
                                    stringByAppendingFormat:@"%c%@", ' ', [input stringValue]];
            [(TTMTask*)task setRawText:newRawText];
        };
        [self forEachSelectedTaskExecuteBlock:appendTextTaskBlock];
    };
    
    [alert beginSheetModalForWindow:self.windowForSheet completionHandler:appendTextHandler];
}

#pragma mark - Priority Methods

- (IBAction)setPriority:(id)sender {
    NSAlert *alert = [NSAlert alertWithMessageText:@"Set Priority"
                                     defaultButton:@"OK"
                                   alternateButton:@"Cancel"
                                       otherButton:nil
                         informativeTextWithFormat:@"Priority:"];
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 50, 24)];
    [input setStringValue:@""];
    [alert setAccessoryView:input];

    // Define the completion handler for the modal sheet.
    void (^priorityHandler)(NSModalResponse returnCode) = ^(NSModalResponse returnCode) {
        if (returnCode != NSAlertDefaultReturn || [[input stringValue] length] == 0) {
            return;
        }
        
        NSString *uppercaseInputString = [[input stringValue] uppercaseString];
        unichar priority = [uppercaseInputString characterAtIndex:0];
        NSCharacterSet *validPriorityCharacters = [NSCharacterSet uppercaseLetterCharacterSet];
        if (![validPriorityCharacters characterIsMember:priority]) {
            return;
        }

        TaskChangeBlock setPriorityTaskBlock = ^(id task, NSUInteger idx, BOOL *stop) {
            [(TTMTask*)task setPriority:priority];
        };
        [self forEachSelectedTaskExecuteBlock:setPriorityTaskBlock];
        
    };

    [alert beginSheetModalForWindow:self.windowForSheet completionHandler:priorityHandler];
}

- (IBAction)increasePriority:(id)sender {
    [self forEachSelectedTaskExecuteBlock:_increaseTaskPriority];
}

- (IBAction)decreasePriority:(id)sender {
    [self forEachSelectedTaskExecuteBlock:_decreaseTaskPriority];
}

- (IBAction)removePriority:(id)sender {
    [self forEachSelectedTaskExecuteBlock:_removeTaskPriority];
}

# pragma mark - Postpone/Due Date Methods

- (IBAction)setDueDate:(id)sender {
    NSAlert *alert = [NSAlert alertWithMessageText:@"Due Date"
                                     defaultButton:@"OK"
                                   alternateButton:@"Cancel"
                                       otherButton:nil
                         informativeTextWithFormat:@"Set the due date:"];
    NSDatePicker *input = [[NSDatePicker alloc] initWithFrame:NSMakeRect(0, 0, 110, 24)];
    [input setDatePickerElements:NSYearMonthDayDatePickerElementFlag];
    [input setTimeZone:[NSTimeZone timeZoneWithName:@"GMT"]];
    [input setDateValue:[TTMDateUtility today]];
    [alert setAccessoryView:input];
    [alert beginSheetModalForWindow:self.windowForSheet
                  completionHandler:^(NSModalResponse returnCode) {
                      if (returnCode == NSAlertDefaultReturn) {
                          TaskChangeBlock setDueDateTaskBlock = ^(id task,
                                                                NSUInteger idx,
                                                                BOOL *stop) {
                              [(TTMTask*)task setDueDate:[input dateValue]];
                          };
                          [self forEachSelectedTaskExecuteBlock:setDueDateTaskBlock];
                      }
                  }];
}

- (IBAction)increaseDueDateByOneDay:(id)sender {
    [self forEachSelectedTaskExecuteBlock:_increaseDueDateByOneDay];
}

- (IBAction)decreaseDueDateByOneDay:(id)sender {
    [self forEachSelectedTaskExecuteBlock:_decreaseDueDateByOneDay];
}

- (IBAction)removeDueDate:(id)sender {
    [self forEachSelectedTaskExecuteBlock:_removeDueDate];
}

- (IBAction)postpone:(id)sender {
    NSAlert *alert = [NSAlert alertWithMessageText:@"Postpone"
                                     defaultButton:@"OK"
                                   alternateButton:@"Cancel"
                                       otherButton:nil
                         informativeTextWithFormat:@"Days to postpone task:"];
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 50, 24)];
    [input setStringValue:@""];
    [alert setAccessoryView:input];
    [alert beginSheetModalForWindow:self.windowForSheet
                  completionHandler:^(NSModalResponse returnCode) {
                         if (returnCode == NSAlertDefaultReturn &&
                             [[input stringValue] length] != 0 &&
                             [input integerValue] != 0) {
                             TaskChangeBlock postponeTaskBlock = ^(id task,
                                                                   NSUInteger idx,
                                                                   BOOL *stop) {
                                 [(TTMTask*)task postponeTask:[input integerValue]];
                         };
                         [self forEachSelectedTaskExecuteBlock:postponeTaskBlock];
                  }
    }];
}

#pragma mark - Sorting Methods

- (void)sortTaskList:(TTMTaskListSortType)sortType {
    
    // set up sort descriptors for the arrayController
    NSSortDescriptor *isPrioritizedDescriptor =
        [[NSSortDescriptor alloc] initWithKey:@"isPrioritized"
                                    ascending:NO
                                     selector:@selector(compare:)];
    NSSortDescriptor *priorityDescriptor =
        [[NSSortDescriptor alloc] initWithKey:@"priority"
                                    ascending:YES
                                     selector:@selector(compare:)];
    NSSortDescriptor *hasProjectsDescriptor =
        [[NSSortDescriptor alloc] initWithKey:@"hasProjects"
                                    ascending:NO
                                     selector:@selector(compare:)];
    NSSortDescriptor *projectDescriptor =
        [[NSSortDescriptor alloc] initWithKey:@"projects"
                                    ascending:YES
                                     selector:@selector(localizedCaseInsensitiveCompare:)];
    NSSortDescriptor *hasContextsDescriptor =
        [[NSSortDescriptor alloc] initWithKey:@"hasContexts"
                                    ascending:NO
                                     selector:@selector(compare:)];
    NSSortDescriptor *contextDescriptor =
        [[NSSortDescriptor alloc] initWithKey:@"contexts"
                                    ascending:YES
                                     selector:@selector(localizedCaseInsensitiveCompare:)];
    NSSortDescriptor *dueStateDescriptor =
        [[NSSortDescriptor alloc] initWithKey:@"dueState"
                                    ascending:YES
                                     selector:@selector(compare:)];
    NSSortDescriptor *dueDateDescriptor =
        [[NSSortDescriptor alloc] initWithKey:@"dueDate"
                                    ascending:YES
                                     selector:@selector(compare:)];
    NSSortDescriptor *creationDateDescriptor =
        [[NSSortDescriptor alloc] initWithKey:@"creationDate"
                                    ascending:YES
                                     selector:@selector(compare:)];
    NSSortDescriptor *completionDateDescriptor =
        [[NSSortDescriptor alloc] initWithKey:@"completionDate"
                                    ascending:YES
                                     selector:@selector(compare:)];
    NSSortDescriptor *taskIdDescriptor =
        [[NSSortDescriptor alloc] initWithKey:@"taskId"
                                    ascending:YES
                                     selector:@selector(compare:)];
    NSSortDescriptor *completedDescriptor =
        [[NSSortDescriptor alloc] initWithKey:@"isCompleted"
                                    ascending:YES
                                     selector:@selector(compare:)];
    NSSortDescriptor *alphabeticalDescriptor =
        [[NSSortDescriptor alloc] initWithKey:@"rawText"
                                    ascending:YES
                                     selector:@selector(localizedCaseInsensitiveCompare:)];
    
    // apply sort descriptors, depending on sort type, to the arrayController
    NSArray *sortDescriptors;
    switch (sortType) {
        case TTMSortOrderInFile:
            sortDescriptors = @[taskIdDescriptor];
            break;
        case TTMSortPriority:
            sortDescriptors = @[isPrioritizedDescriptor, priorityDescriptor, completedDescriptor,
                                dueStateDescriptor, dueDateDescriptor, taskIdDescriptor];
            break;
        case TTMSortProject:
            sortDescriptors = @[hasProjectsDescriptor, projectDescriptor, priorityDescriptor,
                                completedDescriptor, dueDateDescriptor, taskIdDescriptor];
            break;
        case TTMSortContext:
            sortDescriptors = @[hasContextsDescriptor, contextDescriptor, isPrioritizedDescriptor,
                                priorityDescriptor, completedDescriptor, dueDateDescriptor,
                                taskIdDescriptor];
            break;
        case TTMSortDueDate:
            sortDescriptors = @[dueDateDescriptor, isPrioritizedDescriptor, priorityDescriptor,
                                taskIdDescriptor];
            break;
        case TTMSortCreationDate:
            sortDescriptors = @[creationDateDescriptor, taskIdDescriptor];
            break;
        case TTMSortCompletionDate:
            sortDescriptors = @[completionDateDescriptor, taskIdDescriptor];
            break;
        case TTMSortAlphabetical:
            sortDescriptors = @[alphabeticalDescriptor];
            break;
        default:
            sortDescriptors = @[taskIdDescriptor];
            break;
    }
    [self.arrayController setSortDescriptors:sortDescriptors];
    
    // Update the active sort type.
    self.activeSortType = sortType;
    
    // Change the default sort type.
    [[NSUserDefaults standardUserDefaults] setInteger:sortType forKey:@"taskListSortType"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (IBAction)sortByOrderInFile:(id)sender {
    [self sortTaskList:TTMSortOrderInFile];
}

- (IBAction)sortByPriority:(id)sender {
    [self sortTaskList:TTMSortPriority];
}

- (IBAction)sortByProject:(id)sender {
    [self sortTaskList:TTMSortProject];
}

- (IBAction)sortByContext:(id)sender {
    [self sortTaskList:TTMSortContext];
}

- (IBAction)sortByDueDate:(id)sender {
    [self sortTaskList:TTMSortDueDate];
}

- (IBAction)sortByCreationDate:(id)sender {
    [self sortTaskList:TTMSortCreationDate];
}

- (IBAction)sortByCompletionDate:(id)sender {
    [self sortTaskList:TTMSortCompletionDate];
}

- (IBAction)sortByAlphabetical:(id)sender {
    [self sortTaskList:TTMSortAlphabetical];
}

#pragma mark - Filter Methods

- (IBAction)removeTaskListFilter:(id)sender {
    [self changeActiveFilterPredicateToPreset:0];
}

- (IBAction)applyTaskListFilter1:(id)sender {
    [self changeActiveFilterPredicateToPreset:1];
}

- (IBAction)applyTaskListFilter2:(id)sender {
    [self changeActiveFilterPredicateToPreset:2];
}

- (IBAction)applyTaskListFilter3:(id)sender {
    [self changeActiveFilterPredicateToPreset:3];
}

- (IBAction)applyTaskListFilter4:(id)sender {
    [self changeActiveFilterPredicateToPreset:4];
}

- (IBAction)applyTaskListFilter5:(id)sender {
    [self changeActiveFilterPredicateToPreset:5];
}

- (IBAction)applyTaskListFilter6:(id)sender {
    [self changeActiveFilterPredicateToPreset:6];
}

- (IBAction)applyTaskListFilter7:(id)sender {
    [self changeActiveFilterPredicateToPreset:7];
}

- (IBAction)applyTaskListFilter8:(id)sender {
    [self changeActiveFilterPredicateToPreset:8];
}

- (IBAction)applyTaskListFilter9:(id)sender {
    [self changeActiveFilterPredicateToPreset:9];
}

- (void)reapplyActiveFilterPredicate {
    self.activeFilterPredicate = [TTMFilterPredicates getActiveFilterPredicate];
}

- (void)changeActiveFilterPredicateToPreset:(NSUInteger)presetNumber {
    self.activeFilterPredicate = [TTMFilterPredicates
                                  getFilterPredicateFromPresetNumber:presetNumber];
    [TTMFilterPredicates setActiveFilterPredicate:self.activeFilterPredicate];
    self.activeFilterPredicateNumber = presetNumber;
}

#pragma mark - Archiving Methods

- (IBAction)archiveCompletedTasks:(id)sender {
    NSString *archiveFilePath = [[NSUserDefaults standardUserDefaults]
                                 objectForKey:@"archiveFilePath"];
    if ([archiveFilePath length] == 0) {
        return;
    }
    
    // Collect indexes of all completed tasks, and build string containing all completed tasks.
    NSMutableIndexSet *completedTasksIndexSet = [[NSMutableIndexSet alloc] init];
    NSMutableString *completedTasksString = [[NSMutableString alloc] init];
    for (NSUInteger i = 0; i < [[self.arrayController arrangedObjects] count]; i++) {
        TTMTask *task = [[self.arrayController arrangedObjects] objectAtIndex:i];
        if (task.isCompleted) {
            [completedTasksIndexSet addIndex:i];
            [completedTasksString appendString:self.preferredLineEnding]; // assumption may be wrong
            [completedTasksString appendString:task.rawText];
        }
    }
    
    // Abort if no completed tasks were found.
    if ([completedTasksIndexSet count] == 0) {
        return;
    }
    
    @try {
        // Append string containing all completed tasks to archive file.
        [self appendString:completedTasksString toArchiveFile:archiveFilePath];
        
        // Delete all completed tasks.
        [self.arrayController removeObjectsAtArrangedObjectIndexes:completedTasksIndexSet];

        // Refresh the tableView and save the file.
        [self refreshTaskListWithSave:YES];
    }
    @catch (NSException *exception) {
        NSLog(@"Exception: %@", [exception reason]);
        [self refreshTaskListWithSave:NO];
    }
}

- (void)appendString:(NSString*)content toArchiveFile:(NSString*)archiveFilePath {
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:archiveFilePath];
    if (fileHandle) {
        [fileHandle seekToEndOfFile];
        [fileHandle writeData:[content dataUsingEncoding:NSUTF8StringEncoding]];
        [fileHandle closeFile];
    }
    else {
        [content writeToFile:archiveFilePath
                  atomically:YES
                    encoding:NSUTF8StringEncoding
                       error:nil];
    }
}

#pragma mark - NSDocument Method Overrides

// Override normal copy handler to copy selected tasks from the task list.
// This does not get called when the field editor is active.
- (IBAction)copy:(id)sender {
    NSMutableArray *selectedTasksRawText = [[NSMutableArray alloc] init];
    NSIndexSet *selectedRowIndexes = [self.arrayController selectionIndexes];
    
    for (NSUInteger i = [selectedRowIndexes firstIndex];
         i != NSNotFound;
         i = [selectedRowIndexes indexGreaterThanIndex:i]) {
        NSString *rawText = [(TTMTask*)[[self.arrayController arrangedObjects]
                                        objectAtIndex:i] rawText];
        [selectedTasksRawText addObject:rawText];
    }
    
    NSString *clipboardTextString = [selectedTasksRawText componentsJoinedByString:@"\n"];
    [[NSPasteboard generalPasteboard] clearContents];
    [[NSPasteboard generalPasteboard] setString:clipboardTextString forType:NSStringPboardType];
}

- (IBAction)paste:(id)sender {
    [self addNewTasksFromClipboard:self];
}

#pragma mark - Autocompletion Methods

- (void)updateProjectsAndContextsArrays {
    // Collect all the tasks' projects and contexts into sets, which gaurantee uniqueness.
    NSMutableSet *projectsSet = [[NSMutableSet alloc] init];
    NSMutableSet *contextsSet = [[NSMutableSet alloc] init];
    for (TTMTask *task in [self.arrayController arrangedObjects]) {
        [projectsSet addObjectsFromArray:task.projectsArray];
        [contextsSet addObjectsFromArray:task.contextsArray];
    }
    
    // Convert the sets to case-insensitive-sorted arrays.
    NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc]
                                        initWithKey:@""
                                          ascending:YES
                                           selector:@selector(caseInsensitiveCompare:)];
    NSArray *sortDescriptorArray = @[sortDescriptor];
    self.projectsArray = [projectsSet sortedArrayUsingDescriptors:sortDescriptorArray];
    self.contextsArray = [contextsSet sortedArrayUsingDescriptors:sortDescriptorArray];
}

#pragma mark - Menu Item Validation Methods

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    // Note: Parent menu item tags rather than titles are queried so we don't need to worry about
    // internationalization of menu item title strings.
    
    // Check active sort menu item.
    if ([menuItem.parentItem tag] == SORTMENUTAG) {
        if (menuItem.tag == self.activeSortType) {
            [menuItem setState:NSOnState];
        } else {
            [menuItem setState:NSOffState];
        }
    }
    // Check active filter menu item.
     if ([menuItem.parentItem tag] == FILTERMENUTAG) {
        if (menuItem.tag == self.activeFilterPredicateNumber) {
            [menuItem setState:NSOnState];
        } else {
            [menuItem setState:NSOffState];
        }
    }
    return YES;
}

#pragma mark - Find Methods

- (IBAction)moveFocusToSearchBox:(id)sender {
    [self.searchField setRefusesFirstResponder:NO];
    [self.searchField becomeFirstResponder];
    [self.searchField setRefusesFirstResponder:YES];
}

@end