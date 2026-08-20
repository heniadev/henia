/*
Copyright 2026.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package v1alpha1

import (
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
)

// EDIT THIS FILE!  THIS IS SCAFFOLDING FOR YOU TO OWN!
// NOTE: json tags are required.  Any new fields you add must have json tags for the fields to be serialized.

// RepositoryRef declares one repository a Herd spans.
type RepositoryRef struct {
	// url is the clone URL of the repository.
	// +kubebuilder:validation:MinLength=1
	URL string `json:"url"`

	// revision is the branch or tag to track. Naming it is
	// deliberately encouraged rather than defaulted: this project has already
	// been bitten once by a clone with no ref, which took a default branch and
	// produced a tree missing the very code it was meant to build. Empty means
	// the repository's default branch, which is a choice, not an absence.
	// +optional
	Revision string `json:"revision,omitempty"`

	// secretRef names a Secret in the Herd's own namespace holding the
	// credential used to clone this repository. Omit it for a public one.
	// An empty reference is rejected rather than silently accepted: without
	// the rule below, `secretRef: {}` validates, because LocalObjectReference
	// defaults name to the empty string and does not require it.
	// +optional
	// +kubebuilder:validation:XValidation:rule="has(self.name) && self.name != ''",message="secretRef.name must not be empty"
	SecretRef *corev1.LocalObjectReference `json:"secretRef,omitempty"`
}

// HerdSpec defines the desired state of Herd - the declaration a person
// writes. Its counterpart is HerdStatus, which represents the instance
// running from that declaration; there is deliberately no companion
// "Instance" kind, for the reasons recorded on the Herd type below.
type HerdSpec struct {
	// repositories are the repositories this herd spans - one, several, or a
	// monorepo. A herd crosses repository boundaries by construction, which is
	// why there is no separate grouping kind.
	// +kubebuilder:validation:MinItems=1
	Repositories []RepositoryRef `json:"repositories"`

	// targetNamespace is where the instance's components run. Empty means the
	// Herd's own namespace.
	// +optional
	TargetNamespace string `json:"targetNamespace,omitempty"`
}

// HerdStatus defines the observed state of Herd.
type HerdStatus struct {
	// INSERT ADDITIONAL STATUS FIELD - define observed state of cluster
	// Important: Run "make" to regenerate code after modifying this file

	// For Kubernetes API conventions, see:
	// https://github.com/kubernetes/community/blob/master/contributors/devel/sig-architecture/api-conventions.md#typical-status-properties

	// conditions represent the current state of the Herd resource.
	// Each condition has a unique type and reflects the status of a specific aspect of the resource.
	//
	// Standard condition types include:
	// - "Available": the resource is fully functional
	// - "Progressing": the resource is being created or updated
	// - "Degraded": the resource failed to reach or maintain its desired state
	//
	// The status of each condition is one of True, False, or Unknown.
	// +listType=map
	// +listMapKey=type
	// +optional
	Conditions []metav1.Condition `json:"conditions,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:categories=henia,shortName=hd
// +kubebuilder:printcolumn:name="Age",type=date,JSONPath=`.metadata.creationTimestamp`

// Herd is the unit of work Henia manages: a declaration naming the
// repositories to bring under management, and — through its status — the
// running instance created from that declaration.
//
// Declaration and instance are deliberately ONE object rather than two kinds.
// FR-460 says the framework "creates and configures that project's instance
// from the declaration" and FR-450 describes that instance running a loop over
// one or more repositories; read as Kubernetes those are spec and status, not
// two resources. Deployment has no DeploymentInstance. Modelling it as one
// object also dissolves FR-450's grouping question — a herd spans repositories
// by construction.
//
// The name is distinctive on purpose. `Project` collides with
// project.openshift.io, and `Repository`/`Source` sit in territory Flux and
// Knative already occupy; operators reach for `kubectl get <TAB>`, where the
// API group does not disambiguate. The cost is that `Herd` does not explain
// itself, which the categories and shortName above partly offset:
// `kubectl get henia` lists every Henia type.
type Herd struct {
	metav1.TypeMeta `json:",inline"`

	// metadata is a standard object metadata
	// +optional
	metav1.ObjectMeta `json:"metadata,omitzero"`

	// spec defines the desired state of Herd
	// +required
	Spec HerdSpec `json:"spec"`

	// status defines the observed state of Herd
	// +optional
	Status HerdStatus `json:"status,omitzero"`
}

// +kubebuilder:object:root=true

// HerdList contains a list of Herd
type HerdList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitzero"`
	Items           []Herd `json:"items"`
}

func init() {
	SchemeBuilder.Register(func(s *runtime.Scheme) error {
		s.AddKnownTypes(SchemeGroupVersion, &Herd{}, &HerdList{})
		return nil
	})
}
