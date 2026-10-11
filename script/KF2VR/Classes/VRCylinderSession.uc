// A one-handed gun reloaded at the hip while the other hand is busy (one per
// hand, VRInteractiveReload.DualCylinders). A revolver: the cylinder opens
// along the motion its own reload clip shows, a speedloader (the 1858: a
// loaded cylinder) waits at that side's hip, and bringing the open cylinder to
// it loads the gun, which then closes. The stock reload state is entered for
// its server sync and paused at once: none of its animation plays. Stock owns
// the ammunition; seating only completes its reload.
// A magazine gun: its magazine leaves, a fresh one waits at that hip, and
// bringing the gun to it seats it and completes the reload at once.
// Reuses the manual pump's instance-only part controls and their cleanup.
class VRCylinderSession extends VRManualPump;

var int Profile, Capacity;
var VRActionPath ActionPath;
var bool bSpeedloader, bOpened, bSeated, bClosed, bTimersPaused, bSavedPauseAnims;
var float Amount, LastTime;
var StaticMeshComponent Loader;
var name LoaderMeshFor;
var KFWeapon FailedGun;
// Magazine mode: a one-handed magazine gun, its loaded bone and rest frame.
var bool bMagazine;
var name LoadedBone;
var quat MagazineRestQ;
// The seated loader in the cylinder's frame, from the clip's seating moment.
var vector SeatRel;
var quat SeatRel_Q;
var name CylinderBone;
var vector LoaderOffset;
var float SeatRadius, SeatAbove, OpenTime, CloseTime;
var float TouchRadius, TorsoRadius, ForearmLength;
var vector ShoulderOffset;

static function bool Covers(KFWeapon W)
{
    return W != None && class'VRBreakCatalog'.static.CylinderReload(W)
        && class'VRBreakCatalog'.static.IsPath(W.Class);
}

// The magazine profile of a gun, a paired member taking its single gun's.
static function int MagazineIndex(class<KFWeapon> W)
{
    local int I, Best;
    Best = class'VRReloadCatalog'.static.FindClass(W);
    if (Best >= 0 || W == None || !(Left(string(W.Name), 13) ~= "VRWeap_Paired")) return Best;
    for (I = 0; I < class'VRReloadCatalog'.default.Profiles.Length; ++I)
        if (class'VRReloadCatalog'.default.Profiles[I].WeaponClass != None
            && ClassIsChildOf(W, class'VRReloadCatalog'.default.Profiles[I].WeaponClass)
            && (Best < 0 || ClassIsChildOf(class'VRReloadCatalog'.default.Profiles[I].WeaponClass,
                class'VRReloadCatalog'.default.Profiles[Best].WeaponClass)))
            Best = I;
    return Best;
}

// A one-handed magazine gun (pistols, one-handed SMGs) loads at the hip too.
static function bool CoversMagazine(VRWeaponRuntime R)
{
    local VRWeaponPresenter P;
    if (R == None || R.Item == None || R.Presenter == None || !R.Item.bReloadFromMagazine
        || Covers(R.Item) || class'VRBreakCatalog'.static.FindClass(R.Item.Class) >= 0
        || class'VRPumpCatalog'.static.Covers(R.Item) || MagazineIndex(R.Item.Class) < 0) return false;
    P = R.Presenter;
    return P.ActiveProfile >= 0 && P.ActiveProfile < P.WeaponProfiles.Length
        && P.WeaponProfiles[P.ActiveProfile].bOneHanded && P.WeaponProfiles[P.ActiveProfile].bFirearm;
}

static function bool CoversRuntime(VRWeaponRuntime R)
{
    return R != None && (Covers(R.Item) || CoversMagazine(R));
}

function bool Active() { return Gun != None; }

function bool Begin(VRWeaponRuntime R, int Hand)
{
    local name Clip;
    local int I;
    if (Gun != None || R == None || !CoversRuntime(R) || R.Item.MySkelMesh == None) return false;
    bMagazine = !Covers(R.Item);
    Profile = bMagazine ? MagazineIndex(R.Item.Class) : class'VRBreakCatalog'.static.FindClass(R.Item.Class);
    if (Profile < 0) return false;
    // A reload stock already started (the empty gun's automatic reload) is
    // taken over as it is; otherwise this press starts one.
    if (!R.Item.IsInState('Reloading'))
    {
        if (!R.Item.CanReload()) return false;
        R.StartAction(class'KFWeapon'.const.RELOAD_FIREMODE);
        R.Item.StopFire(class'KFWeapon'.const.RELOAD_FIREMODE);
        if (!R.Item.IsInState('Reloading')) return false;
    }
    else if (R.Item == FailedGun) return false;
    FailedGun = None;
    Gun = R.Item; Runtime = R; GunHand = Hand;
    RootBone = 'RW_Weapon';
    if (R.Presenter != None && R.Presenter.ActiveProfile >= 0)
        RootBone = R.Presenter.WeaponProfiles[R.Presenter.ActiveProfile].RootBone;
    bTimersPaused = false;
    PauseStock();
    if (bMagazine) return BeginMagazine();
    Capacity = class'VRBreakCatalog'.default.Profiles[Profile].Capacity;
    bSpeedloader = class'VRBreakCatalog'.default.Profiles[Profile].ClipBone == 'RW_Speedloader';
    CylinderBone = 'RW_Cylinder';
    Clip = Gun.WeaponAnimSeqNode != None ? Gun.WeaponAnimSeqNode.AnimSeqName : '';
    if (Clip == '') Clip = class'KFWeapon'.const.ReloadEmptyMagAnim;
    ActionPath = new(self) class'VRActionPath';
    for (I = 0; I < 3; ++I)
    {
        ActionPath.Bones[I] = class'VRBreakCatalog'.default.Profiles[Profile].PathBones[I];
        if (ActionPath.Bones[I] != '') ActionPath.BoneCount = I + 1;
    }
    if (!ActionPath.SampleClip(Bridge, Gun, RootBone, Clip, Bridge.HandBone(0))
        || Gun.MySkelMesh.MatchRefBone(CylinderBone) < 0)
    { Abort("sample"); return false; }
    Parts.Length = 0;
    for (I = 0; I < ActionPath.BoneCount; ++I) AddPart(ActionPath.Ref, ActionPath.Bones[I], false);
    Bridge.AttachComponent(ActionPath.Ref);
    ActionPath.PoseRef(0);
    // The cylinder, its rounds and the extractor ride the swing-out pivot.
    AddPart(ActionPath.Ref, CylinderBone, bSpeedloader);
    for (I = 1; I <= Capacity; ++I) AddPart(ActionPath.Ref, name("RW_Bullets" $ I), bSpeedloader);
    if (bSpeedloader)
    {
        AddPart(ActionPath.Ref, 'RW_ExtractorPin', true);
        AddPart(ActionPath.Ref, 'RW_ExtractorHead', true);
    }
    SampleSeat();
    Bridge.DetachComponent(ActionPath.Ref);
    Tree = AnimTree(Gun.MySkelMesh.Animations);
    if (Tree == None || Tree == Gun.MySkelMesh.AnimTreeTemplate || Parts.Length <= ActionPath.BoneCount)
    { Tree = None; Abort("controls"); return false; }
    bSavedPooling = Tree.bEnablePooling; Tree.bEnablePooling = false;
    for (I = 0; I < Parts.Length; ++I) Parts[I].Control = AppendControl(Parts[I].Bone);
    Gun.MySkelMesh.InitSkelControls();
    if (!PrepareLoader()) { Abort("loader"); return false; }
    Amount = 0; bOpened = false; bSeated = false; bClosed = false; LastTime = 0;
    PlayCue(class'VRBreakCatalog'.default.Profiles[Profile].Open);
    `log("KF2VR_DUAL_CYLINDER phase=begin weapon=" $ Gun.Class @ "hand=" $ Hand @ "clip=" $ Clip
        @ "ammo=" $ Gun.AmmoCount[0] @ "spare=" $ Gun.GetSpareAmmoForHUD() @ "speedloader=" $ bSpeedloader);
    return true;
}

// The loaded magazine leaves the gun; the fresh one waits at the hip in the
// magazine's own frame, as it sits in the gun.
function bool BeginMagazine()
{
    local StaticMesh Mesh;
    local int I;
    LoadedBone = '';
    if (class'VRReloadCatalog'.default.Profiles[Profile].LoadedBone != '')
        LoadedBone = class'VRReloadCatalog'.static.MagazineBone(Profile, false);
    else for (I = 0; I < Owner.LoadedBoneNames.Length && LoadedBone == ''; ++I)
        if (Gun.MySkelMesh.MatchRefBone(Owner.LoadedBoneNames[I]) >= 0) LoadedBone = Owner.LoadedBoneNames[I];
    if (LoadedBone == '' || Gun.MySkelMesh.MatchRefBone(LoadedBone) < 0 || Gun.MySkelMesh.MatchRefBone(RootBone) < 0)
    { Abort("magazine-bone"); return false; }
    Mesh = StaticMesh(DynamicLoadObject("KF2VRHands.VRAmmo_" $ Gun.MySkelMesh.SkeletalMesh.Name, class'StaticMesh', true));
    if (Mesh == None) { Abort("magazine-asset"); return false; }
    if (Loader == None) Loader = Owner.MakeComponent(Mesh, None);
    Loader.SetStaticMesh(Mesh);
    Loader.SetMaterial(0, Gun.MySkelMesh.GetMaterial(class'VRReloadCatalog'.default.Profiles[Profile].MaterialIndex));
    Loader.SetMaterial(1, Gun.MySkelMesh.GetMaterial(class'VRReloadCatalog'.default.Profiles[Profile].Section1MaterialIndex));
    if (class'VRReloadCatalog'.default.Profiles[Profile].Section2MaterialIndex > 0)
        Loader.SetMaterial(2, Gun.MySkelMesh.GetMaterial(class'VRReloadCatalog'.default.Profiles[Profile].Section2MaterialIndex));
    Loader.SetScale(GunScale());
    MagazineRestQ = QuatProduct(QuatInvert(RootQ()), Gun.MySkelMesh.GetBoneQuaternion(LoadedBone));
    Gun.MySkelMesh.HideBoneByName(LoadedBone, PBO_None);
    Amount = 0; bOpened = true; bSeated = false; bClosed = false; LastTime = 0;
    Owner.Pulse(1 << GunHand, 0.3, 0.02);
    `log("KF2VR_DUAL_CYLINDER phase=begin weapon=" $ Gun.Class @ "hand=" $ GunHand @ "magazine=" $ LoadedBone
        @ "ammo=" $ Gun.AmmoCount[0] @ "spare=" $ Gun.GetSpareAmmoForHUD());
    return true;
}

// The clip's seating moment: the loader nearest the cylinder after the
// opening. The 1858's loader is the cylinder itself, seated where it sits.
function SampleSeat()
{
    local name ClipBone;
    local vector CylP, LoadP, BestP;
    local quat CylQ, LoadQ, BestQ;
    local float T, D, Best, Length;
    local int I;
    SeatRel = vect(0,0,0); SeatRel_Q = QuatFromRotator(rot(0,0,0));
    ClipBone = class'VRBreakCatalog'.default.Profiles[Profile].ClipBone;
    if (ClipBone == CylinderBone || ActionPath.Ref.MatchRefBone(ClipBone) < 0) return;
    Length = ActionPath.RefSeq.AnimSeq.SequenceLength;
    Best = 1000000;
    for (I = 0; I <= 60; ++I)
    {
        T = ActionPath.OpenTime + (Length - ActionPath.OpenTime) * float(I) / 60.0;
        ActionPath.PoseRef(T);
        ActionPath.RefRelative(CylinderBone, CylP, CylQ);
        ActionPath.RefRelative(ClipBone, LoadP, LoadQ);
        D = VSize(LoadP - CylP);
        if (D < Best)
        {
            Best = D;
            BestP = QuatRotateVector(QuatInvert(CylQ), LoadP - CylP);
            BestQ = QuatProduct(QuatInvert(CylQ), LoadQ);
        }
    }
    if (Best < 20) { SeatRel = BestP; SeatRel_Q = BestQ; }
}

// The gun's own cut ammunition (KF2VRHands.VRAmmo_<rig>): the .500's and
// Rhino's speedloader, the 1858's loaded cylinder.
function bool PrepareLoader()
{
    local StaticMesh Mesh;
    local SkeletalMesh RoundMesh;
    local MaterialInterface Surface1;
    local name MeshName;
    MeshName = Gun.MySkelMesh.SkeletalMesh.Name;
    Mesh = StaticMesh(DynamicLoadObject("KF2VRHands.VRAmmo_" $ MeshName, class'StaticMesh', true));
    if (Mesh == None) return false;
    if (Loader == None) Loader = Owner.MakeComponent(Mesh, None);
    Loader.SetStaticMesh(Mesh);
    Loader.SetMaterial(0, Gun.MySkelMesh.GetMaterial(class'VRBreakCatalog'.default.Profiles[Profile].MaterialIndex));
    Surface1 = Gun.MySkelMesh.GetMaterial(class'VRBreakCatalog'.default.Profiles[Profile].Section1MaterialIndex);
    if (class'VRBreakCatalog'.default.Profiles[Profile].Section1MaterialMesh != "")
    {
        RoundMesh = SkeletalMesh(DynamicLoadObject(class'VRBreakCatalog'.default.Profiles[Profile].Section1MaterialMesh, class'SkeletalMesh', true));
        if (RoundMesh != None && RoundMesh.Materials.Length > 0) Surface1 = RoundMesh.Materials[0];
    }
    Loader.SetMaterial(1, Surface1);
    Loader.SetScale(GunScale());
    LoaderMeshFor = MeshName;
    return true;
}

function PauseStock()
{
    if (bTimersPaused || Gun == None) return;
    bTimersPaused = true;
    Gun.PauseTimer(true, 'ReloadAmmoTimer');
    Gun.PauseTimer(true, 'ReloadStatusTimer');
    bSavedPauseAnims = Gun.MySkelMesh.bPauseAnims;
    Gun.MySkelMesh.bPauseAnims = true;
}

function ResumeStock()
{
    if (!bTimersPaused || Gun == None) return;
    bTimersPaused = false;
    Gun.PauseTimer(false, 'ReloadAmmoTimer');
    Gun.PauseTimer(false, 'ReloadStatusTimer');
    if (Gun.MySkelMesh != None) Gun.MySkelMesh.bPauseAnims = bSavedPauseAnims;
}

function PlayCue(string Events)
{
    local AkEvent Sound;
    Sound = class'VRBreakCatalog'.static.LoadSound(Gun.Class, Events);
    if (Sound != None) Gun.PlaySoundBase(Sound, true);
}

// The hip loader faces up for a gun brought down muzzle first, top forward.
function quat DownQ()
{
    local rotator R;
    R = Bridge.BodyYaw();
    R.Pitch = -16384; R.Roll = 0;
    return QuatFromRotator(R);
}

function vector RestCylinderLocal(out quat Q)
{
    local int I;
    for (I = 0; I < Parts.Length; ++I)
        if (Parts[I].Bone == CylinderBone) { Q = Parts[I].IdleLocalQ; return Parts[I].IdleLocal; }
    Q = QuatFromRotator(rot(0,0,0));
    return vect(0,0,0);
}

function HipLoader(out vector At, out quat Q)
{
    local quat CylLocalQ, Down;
    Down = DownQ();
    if (bMagazine) Q = QuatProduct(Down, MagazineRestQ);
    else
    {
        RestCylinderLocal(CylLocalQ);
        Q = QuatProduct(Down, QuatProduct(CylLocalQ, SeatRel_Q));
    }
    At = Owner.Bridge.AmmoPouchPosition(GunHand, LoaderOffset);
}

// Where a seated loader sits on the gun now (the open cylinder's frame).
function vector SeatTarget(out quat Q)
{
    local quat CylQ;
    CylQ = Gun.MySkelMesh.GetBoneQuaternion(CylinderBone);
    Q = QuatProduct(CylQ, SeatRel_Q);
    return Gun.MySkelMesh.GetBoneLocation(CylinderBone) + QuatRotateVector(CylQ, SeatRel * GunScale());
}

function ShowRounds(bool bShow)
{
    local KFWeap_PistolBase Revolver;
    local name Bone;
    local int I;
    if (bMagazine)
    {
        if (bShow) Gun.MySkelMesh.UnHideBoneByName(LoadedBone);
        else Gun.MySkelMesh.HideBoneByName(LoadedBone, PBO_None);
        return;
    }
    if (!bSpeedloader)
    {
        // The 1858 swaps its whole cylinder.
        if (bShow) Gun.MySkelMesh.UnHideBoneByName(CylinderBone);
        else Gun.MySkelMesh.HideBoneByName(CylinderBone, PBO_None);
        return;
    }
    Revolver = KFWeap_PistolBase(Gun);
    if (Revolver != None && Revolver.BulletMeshComponents.Length > 0)
    {
        for (I = 0; I < Revolver.BulletMeshComponents.Length; ++I)
            if (Revolver.BulletMeshComponents[I] != None) Revolver.BulletMeshComponents[I].SetHidden(!bShow);
        return;
    }
    for (I = 1; I <= 8; ++I)
    {
        Bone = name("RW_Bullets" $ I);
        if (Gun.MySkelMesh.MatchRefBone(Bone) == INDEX_NONE) continue;
        if (bShow) Gun.MySkelMesh.UnHideBoneByName(Bone);
        else Gun.MySkelMesh.HideBoneByName(Bone, PBO_None);
    }
}

static function float SegmentDistance(vector P, vector A, vector B)
{
    local vector AB;
    local float T;
    AB = B - A;
    T = VSizeSq(AB) > 0.01 ? FClamp(((P - A) dot AB) / VSizeSq(AB), 0, 1) : 0.0;
    return VSize(P - (A + AB * T));
}

// The open cylinder knocked against the body: the torso, the other hand or
// arm, or the other gun. Any of them loads it, as the hip does.
function bool Touching(vector P)
{
    local int Other;
    local vector Hand, Elbow, Shoulder, Pivot, Root;
    local quat Q;
    local VRWeaponRuntime R;
    Other = 1 - GunHand;
    Pivot = Bridge.BodyPivot();
    if (VSize((P - Pivot) * vect(1,1,0)) <= TorsoRadius && P.Z <= Pivot.Z && P.Z >= Pivot.Z - 80) return true;
    if ((Bridge.NativeValidMask & (1 << Other)) != 0)
    {
        Hand = Bridge.Hands[Other].Position;
        Elbow = Hand - vector(Other == 0 ? Bridge.LeftRotation : Bridge.RightRotation) * ForearmLength;
        Shoulder = ShoulderOffset;
        if (Other == 1) Shoulder.Y = -Shoulder.Y;
        Shoulder = Pivot + (Shoulder >> Bridge.BodyYaw());
        if (VSize(P - Hand) <= TouchRadius || SegmentDistance(P, Hand, Elbow) <= TouchRadius
            || SegmentDistance(P, Elbow, Shoulder) <= TouchRadius) return true;
    }
    R = Owner.InputOwner.Inventory.Registry.GetPrimary(Other);
    if (R != None && R.Item != None && R.Item != Gun && R.Item.MySkelMesh != None
        && R.Item.MySkelMesh.MatchRefBone('RW_Weapon') >= 0)
    {
        Root = R.Item.MySkelMesh.GetBoneLocation('RW_Weapon');
        Q = R.Item.MySkelMesh.GetBoneQuaternion('RW_Weapon');
        if (SegmentDistance(P, Root - QuatRotateVector(Q, vect(8,0,0)), Root + QuatRotateVector(Q, vect(28,0,0))) <= TouchRadius)
            return true;
    }
    return false;
}

function bool StillValid()
{
    return Gun != None && !Gun.bDeleteMe && Gun.MySkelMesh != None && Runtime != None
        && Runtime.Item == Gun && Runtime.IsCurrent() && Runtime.PrimaryHand == GunHand
        && Gun.IsInState('Reloading') && Owner.Enabled();
}

function Tick()
{
    local float Time, DT;
    local vector At, Target;
    local quat Q;
    if (Gun == None) return;
    if (!StillValid()) { Abort("ended"); return; }
    Time = Owner.Now(); DT = (LastTime > 0) ? Time - LastTime : 0.0; LastTime = Time;
    if (DT <= 0 || DT > 0.1) return;
    if ((Bridge.NativeValidMask & (1 << GunHand)) == 0) return;
    if (!bOpened)
    {
        Amount = FMin(1, Amount + DT / (OpenTime * Gun.GetReloadRateScale()));
        if (Amount >= 1)
        {
            bOpened = true;
            ShowRounds(false);
            Owner.Pulse(1 << GunHand, 0.45, 0.03);
        }
        return;
    }
    if (!bSeated)
    {
        // Generous: the cylinder near that hip, or anywhere lower on its side,
        // loads it. Dropping the guns to the hips is enough.
        HipLoader(At, Q);
        Target = Gun.MySkelMesh.GetBoneLocation(bMagazine ? LoadedBone : CylinderBone);
        if ((VSize((Target - At) * vect(1,1,0)) <= SeatRadius && Target.Z - At.Z <= SeatAbove)
            || Touching(Target))
        {
            bSeated = true;
            Loader.SetHidden(true);
            ShowRounds(true);
            Owner.Pulse(1 << GunHand, 0.7, 0.04);
            if (bMagazine) { Complete(); return; }
            PlayCue(class'VRBreakCatalog'.default.Profiles[Profile].InsertB);
        }
        return;
    }
    Amount = FMax(0, Amount - DT / CloseTime);
    if (Amount <= 0) Complete();
}

// Credited exactly as stock's own completion; the rest of its clip never plays.
function Complete()
{
    local KFWeapon W;
    W = Gun;
    bClosed = true;
    Gun.ClearTimer('ReloadAmmoTimer');
    Gun.ClearTimer('ReloadStatusTimer');
    ResumeStock();
    Gun.PerformReload();
    Gun.ReloadComplete();
    if (Gun.IdleAnims.Length > 0) Gun.PlayAnimation(Gun.IdleAnims[0], 0.0, true, 0.0);
    Gun.ToggleAdditiveBobAnim(!Gun.bUsingSights);
    if (!bMagazine) PlayCue(class'VRBreakCatalog'.default.Profiles[Profile].Close);
    Owner.Pulse(1 << GunHand, 0.8, 0.04);
    `log("KF2VR_DUAL_CYLINDER phase=closed weapon=" $ W.Class @ "hand=" $ GunHand @ "ammo=" $ W.AmmoCount[0]);
    Unbind();
}

// Interrupted: hand the reload back to stock with the gun as it was. That
// reload is not taken over again (stock finishes it).
function Abort(string Reason)
{
    FailedGun = Gun;
    if (Gun != None)
        `log("KF2VR_DUAL_CYLINDER phase=abort reason=" $ Reason @ "weapon=" $ Gun.Class @ "hand=" $ GunHand);
    if (Gun != None && !Gun.bDeleteMe && Gun.MySkelMesh != None) ShowRounds(true);
    ResumeStock();
    Unbind();
}

function Unbind()
{
    if (Loader != None) Loader.SetHidden(true);
    bMagazine = false; LoadedBone = '';
    bTimersPaused = false;
    ActionPath = None;
    super.Unbind();
}

function Shutdown()
{
    if (Gun != None) Abort("shutdown");
    if (Loader != None) { Bridge.DetachComponent(Loader); Loader = None; }
    super.Shutdown();
}

function PlaceVisuals()
{
    local int I;
    local vector P, PivotP, At;
    local quat Q, PivotQ, Turn;
    if (Gun == None || Gun.bDeleteMe || Gun.MySkelMesh == None) return;
    if (bMagazine)
    {
        if ((Bridge.NativeValidMask & (1 << GunHand)) != 0 && !bSeated)
        {
            HipLoader(At, Q);
            Loader.SetTranslation(At);
            Loader.SetRotation(QuatToRotator(Q));
            Loader.SetHidden(false);
        }
        else Loader.SetHidden(true);
        return;
    }
    if (Tree == None) return;
    if ((Bridge.NativeValidMask & (1 << GunHand)) == 0)
    {
        for (I = 0; I < Parts.Length; ++I) Parts[I].Control.SetSkelControlStrength(0, 0);
        Loader.SetHidden(true);
        Gun.MySkelMesh.ForceSkelUpdate();
        return;
    }
    for (I = 0; I < ActionPath.BoneCount; ++I)
    {
        ActionPath.PoseAt(Amount, I, P, Q);
        Parts[I].Control.BoneTranslation = RootPos() + QuatRotateVector(RootQ(), P * GunScale());
        Parts[I].Control.BoneRotation = QuatToRotator(QuatProduct(RootQ(), Q));
        Parts[I].Control.SetSkelControlStrength(1, 0);
    }
    ActionPath.PoseAt(Amount, 0, PivotP, PivotQ);
    Turn = QuatProduct(PivotQ, QuatInvert(Parts[0].IdleLocalQ));
    for (I = ActionPath.BoneCount; I < Parts.Length; ++I)
    {
        P = Parts[I].IdleLocal; Q = Parts[I].IdleLocalQ;
        if (Parts[I].bTravels)
        {
            P = PivotP + QuatRotateVector(Turn, P - Parts[0].IdleLocal);
            Q = QuatProduct(Turn, Q);
        }
        Parts[I].Control.BoneTranslation = RootPos() + QuatRotateVector(RootQ(), P * GunScale());
        Parts[I].Control.BoneRotation = QuatToRotator(QuatProduct(RootQ(), Q));
        Parts[I].Control.SetSkelControlStrength(1, 0);
    }
    Gun.MySkelMesh.ForceSkelUpdate(); Gun.MySkelMesh.ForceUpdate(true);
    if (bOpened && !bSeated)
    {
        HipLoader(At, Q);
        Loader.SetTranslation(At);
        Loader.SetRotation(QuatToRotator(Q));
        Loader.SetHidden(false);
    }
    else Loader.SetHidden(true);
}

defaultproperties
{
    // Each side's hip, a little forward of the magazine pouch's line.
    LoaderOffset=(X=8,Y=-24,Z=-30)
    SeatRadius=26
    SeatAbove=14
    TouchRadius=12
    TorsoRadius=20
    ForearmLength=28
    // From the body pivot (base of the neck): the left shoulder.
    ShoulderOffset=(X=0,Y=-18,Z=-6)
    OpenTime=0.25
    CloseTime=0.12
}
