//+build windows

package dmsgpty

import "github.com/creack/pty"

// Start starts the pty.
func (sc *PtyClient) Start(name string, arg ...string) error {
	return sc.StartWithSize(name, arg, &pty.Winsize{Rows: 80, Cols: 30})
}
