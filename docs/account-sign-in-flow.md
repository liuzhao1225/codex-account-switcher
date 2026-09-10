# Adding an account: navigation and cancellation

The shared controller owns login, cancellation and saving. macOS and Windows keep management reachable while browser sign-in is pending.

| Action or event | Behavior |
| --- | --- |
| Manage accounts → Add account | Start one login attempt and open the browser. Show the waiting hint and Cancel Adding Account. Ignore duplicate starts. |
| Close the authentication tab | Continue waiting: a browser tab closing does not send a login cancellation event. Cancel from Manage accounts to start again. |
| Hide the menu/window, then reopen it during login | Return to Manage accounts with an enabled cancel action. |
| Back to the switching page during login | Preserve the pending attempt. Keep Manage accounts available; account/provider switching remains disabled until login ends. |
| Cancel Adding Account | Cancel the task and stop its app-server session. Remove the unregistered profile directory. Keep the attempt busy until cleanup completes, then restore Add account. |
| Login succeeds | Save the account and show it in management. Do not automatically switch the active Codex account. |
| Login fails, browser launch fails, or login times out | Remove the incomplete profile and show the actual error. Starting another attempt clears the previous error. |
| Incomplete-profile cleanup fails | Show the cleanup failure instead of reporting a clean cancellation. |

Closing or navigating away from the application UI does not cancel a login. Cancellation is explicit. The current app-server completion wait times out after ten minutes; users can cancel earlier.

## Regression evidence

The former macOS popover reset every reopen to the switching page and disabled Manage accounts while `isAddingAccount` was true. That combination hid the existing cancel action. Reopening now selects management when login is pending, and the management navigation remains enabled.

Shared controller checks exercise failure → retry, duplicate starts, refreshing while login remains pending, cancel → cleanup → retry, and preservation of the active credential. macOS transport checks cancel an actual isolated subprocess session without opening a browser. Windows UI checks exercise Add → Back → Hide → Reopen → Cancel and verify that Add becomes usable again.
