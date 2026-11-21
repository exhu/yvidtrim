module yvidtrim.model;

import yguilib.model : VersionedModel;
import yguilib.widget.layout_components : AlignItems;

final class MainModel : VersionedModel {
  bool toggleVisible = true;
  float alphaValue = 0.3f;
  bool qPressed;
  bool aPressed;
  AlignItems alignItems;
}
