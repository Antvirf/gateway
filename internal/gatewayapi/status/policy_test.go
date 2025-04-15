// Copyright Envoy Gateway Authors
// SPDX-License-Identifier: Apache-2.0
// The full text of the Apache license is available in the LICENSE file at
// the root of the repo.

package status

import (
	"strings"
	"testing"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	gwapiv1a2 "sigs.k8s.io/gateway-api/apis/v1alpha2"
)

func TestSetConditionForPolicyAncestorMessageTruncation(t *testing.T) {
	// Create a message that exceeds the maximum length
	longMessage := strings.Repeat("a", MaxConditionMessageLength+100)
	expectedTruncatedMessage := longMessage[:MaxConditionMessageLength] + " [truncated]"

	// Create a policy status
	policyStatus := &gwapiv1a2.PolicyStatus{}

	// Create an ancestor reference
	ancestorRef := gwapiv1a2.ParentReference{
		Name: "test-gateway",
	}

	// Set a condition with the long message
	SetConditionForPolicyAncestor(
		policyStatus,
		ancestorRef,
		"test-controller",
		gwapiv1a2.PolicyConditionAccepted,
		metav1.ConditionFalse,
		gwapiv1a2.PolicyReasonInvalid,
		longMessage,
		1,
	)

	// Verify that the message was truncated
	if len(policyStatus.Ancestors) != 1 {
		t.Fatalf("Expected 1 ancestor, got %d", len(policyStatus.Ancestors))
	}

	if len(policyStatus.Ancestors[0].Conditions) != 1 {
		t.Fatalf("Expected 1 condition, got %d", len(policyStatus.Ancestors[0].Conditions))
	}

	actualMessage := policyStatus.Ancestors[0].Conditions[0].Message
	if actualMessage != expectedTruncatedMessage {
		t.Errorf("Expected truncated message, got: %s", actualMessage)
	}

	// Test with a message that doesn't exceed the maximum length
	shortMessage := "This is a short message"
	policyStatus = &gwapiv1a2.PolicyStatus{}

	SetConditionForPolicyAncestor(
		policyStatus,
		ancestorRef,
		"test-controller",
		gwapiv1a2.PolicyConditionAccepted,
		metav1.ConditionTrue,
		gwapiv1a2.PolicyReasonAccepted,
		shortMessage,
		1,
	)

	// Verify that the message was not truncated
	if len(policyStatus.Ancestors) != 1 {
		t.Fatalf("Expected 1 ancestor, got %d", len(policyStatus.Ancestors))
	}

	if len(policyStatus.Ancestors[0].Conditions) != 1 {
		t.Fatalf("Expected 1 condition, got %d", len(policyStatus.Ancestors[0].Conditions))
	}

	actualMessage = policyStatus.Ancestors[0].Conditions[0].Message
	if actualMessage != shortMessage {
		t.Errorf("Expected original message, got: %s", actualMessage)
	}
}
