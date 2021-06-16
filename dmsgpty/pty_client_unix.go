//+build !windows

package dmsgpty

import (
	"github.com/creack/pty"
	"os"
)

// Start starts the pty
func (sc *PtyClient) Start(name string, arg ...string) error {
	size, err := pty.GetsizeFull(os.Stdin)
	if err != nil {
		sc.log.WithError(err).Warn("failed to obtain terminal size")
		size = nil
	}
	return sc.StartWithSize(name, arg, size)
}

