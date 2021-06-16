//+build windows

package dmsgpty

import (
	"context"
	"time"
)

const (
	windowsPollResizeDuration = 1 * time.Second
)

// ptyResizeLoop informs the remote of changes to the local CLI terminal window size.
func ptyResizeLoop(_ context.Context, _ *PtyClient) error {
	// TODO
	return nil
}
