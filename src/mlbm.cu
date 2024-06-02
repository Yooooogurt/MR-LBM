#include "mlbm.cuh"

__global__ void gpuMomCollisionStream(
    dfloat *fMom, unsigned int *dNodeType,
    dfloat *fGhostX_0, dfloat *fGhostX_1,
    dfloat *fGhostY_0, dfloat *fGhostY_1,
    dfloat *fGhostZ_0, dfloat *fGhostZ_1,
    dfloat *gGhostX_0, dfloat *gGhostX_1,
    dfloat *gGhostY_0, dfloat *gGhostY_1,
    dfloat *gGhostZ_0, dfloat *gGhostZ_1,
    #ifdef SECOND_DIST 
    dfloat *g_fGhostX_0, dfloat *g_fGhostX_1,
    dfloat *g_fGhostY_0, dfloat *g_fGhostY_1,
    dfloat *g_fGhostZ_0, dfloat *g_fGhostZ_1,
    dfloat *g_gGhostX_0, dfloat *g_gGhostX_1,
    dfloat *g_gGhostY_0, dfloat *g_gGhostY_1,
    dfloat *g_gGhostZ_0, dfloat *g_gGhostZ_1,
    #endif 
    #ifdef DENSITY_CORRECTION
    dfloat *d_mean_rho,
    #endif
    #ifdef BC_FORCES
    dfloat *d_BC_Fx, dfloat *d_BC_Fy, dfloat *d_BC_Fz,
    #endif 
    unsigned int step,
    bool save)
{
    const int x = threadIdx.x + blockDim.x * blockIdx.x;
    const int y = threadIdx.y + blockDim.y * blockIdx.y;
    const int z = threadIdx.z + blockDim.z * blockIdx.z;
    if (x >= NX || y >= NY || z >= NZ)
        return;
    dfloat pop[Q];
    #ifdef SECOND_DIST
    dfloat gNode[GQ];
    #endif
    dfloat pics2;
    dfloat multiplyTerm;

    #ifdef DYNAMIC_SHARED_MEMORY
    extern __shared__ dfloat s_pop[]; 
    #else
    __shared__ dfloat s_pop[BLOCK_LBM_SIZE * (Q - 1)];
    #endif

    const unsigned short int xp1 = (threadIdx.x + 1 + BLOCK_NX) % BLOCK_NX;
    const unsigned short int xm1 = (threadIdx.x - 1 + BLOCK_NX) % BLOCK_NX;

    const unsigned short int yp1 = (threadIdx.y + 1 + BLOCK_NY) % BLOCK_NY;
    const unsigned short int ym1 = (threadIdx.y - 1 + BLOCK_NY) % BLOCK_NY;

    const unsigned short int zp1 = (threadIdx.z + 1 + BLOCK_NZ) % BLOCK_NZ;
    const unsigned short int zm1 = (threadIdx.z - 1 + BLOCK_NZ) % BLOCK_NZ;

    const int tx = threadIdx.x;
    const int ty = threadIdx.y;
    const int tz = threadIdx.z;
    
    const int bx = blockIdx.x;
    const int by = blockIdx.y;
    const int bz = blockIdx.z;

    const int txm1 = (tx-1+BLOCK_NX)%BLOCK_NX;
    const int txp1 = (tx+1+BLOCK_NX)%BLOCK_NX;

    const int tym1 = (ty-1+BLOCK_NY)%BLOCK_NY;
    const int typ1 = (ty+1+BLOCK_NY)%BLOCK_NY;

    const int tzm1 = (tz-1+BLOCK_NZ)%BLOCK_NZ;
    const int tzp1 = (tz+1+BLOCK_NZ)%BLOCK_NZ;

    const int bxm1 = (bx-1+NUM_BLOCK_X)%NUM_BLOCK_X;
    const int bxp1 = (bx+1+NUM_BLOCK_X)%NUM_BLOCK_X;

    const int bym1 = (by-1+NUM_BLOCK_Y)%NUM_BLOCK_Y;
    const int byp1 = (by+1+NUM_BLOCK_Y)%NUM_BLOCK_Y;

    const int bzm1 = (bz-1+NUM_BLOCK_Z)%NUM_BLOCK_Z;
    const int bzp1 = (bz+1+NUM_BLOCK_Z)%NUM_BLOCK_Z;

    // Load moments from global memory

    //rho'
    unsigned int nodeType = dNodeType[idxScalarBlock(threadIdx.x, threadIdx.y, threadIdx.z,blockIdx.x, blockIdx.y, blockIdx.z)];
    if (nodeType == 0b11111111)  return;
    dfloat rhoVar = RHO_0 + fMom[idxMom(threadIdx.x, threadIdx.y, threadIdx.z, M_RHO_INDEX, blockIdx.x, blockIdx.y, blockIdx.z)];
    dfloat ux_t30     = F_M_I_SCALE*fMom[idxMom(threadIdx.x, threadIdx.y, threadIdx.z, M_UX_INDEX, blockIdx.x, blockIdx.y, blockIdx.z)];
    dfloat uy_t30     = F_M_I_SCALE*fMom[idxMom(threadIdx.x, threadIdx.y, threadIdx.z, M_UY_INDEX, blockIdx.x, blockIdx.y, blockIdx.z)];
    dfloat uz_t30     = F_M_I_SCALE*fMom[idxMom(threadIdx.x, threadIdx.y, threadIdx.z, M_UZ_INDEX, blockIdx.x, blockIdx.y, blockIdx.z)];
    dfloat m_xx_t45   = F_M_II_SCALE*fMom[idxMom(threadIdx.x, threadIdx.y, threadIdx.z, M_MXX_INDEX, blockIdx.x, blockIdx.y, blockIdx.z)];
    dfloat m_xy_t90   = F_M_IJ_SCALE*fMom[idxMom(threadIdx.x, threadIdx.y, threadIdx.z, M_MXY_INDEX, blockIdx.x, blockIdx.y, blockIdx.z)];
    dfloat m_xz_t90   = F_M_IJ_SCALE*fMom[idxMom(threadIdx.x, threadIdx.y, threadIdx.z, M_MXZ_INDEX, blockIdx.x, blockIdx.y, blockIdx.z)];
    dfloat m_yy_t45   = F_M_II_SCALE*fMom[idxMom(threadIdx.x, threadIdx.y, threadIdx.z, M_MYY_INDEX, blockIdx.x, blockIdx.y, blockIdx.z)];
    dfloat m_yz_t90   = F_M_IJ_SCALE*fMom[idxMom(threadIdx.x, threadIdx.y, threadIdx.z, M_MYZ_INDEX, blockIdx.x, blockIdx.y, blockIdx.z)];
    dfloat m_zz_t45   = F_M_II_SCALE*fMom[idxMom(threadIdx.x, threadIdx.y, threadIdx.z, M_MZZ_INDEX, blockIdx.x, blockIdx.y, blockIdx.z)];

    #if defined(NON_NEWTONIAN_FLUID) || defined(LES_MODEL)
        #ifdef NON_NEWTONIAN_FLUID
            dfloat omegaVar = fMom[idxMom(threadIdx.x, threadIdx.y, threadIdx.z, M_OMEGA_INDEX, blockIdx.x, blockIdx.y, blockIdx.z)];
        #else
            dfloat omegaVar = OMEGA;
        #endif
    dfloat t_omegaVar = 1 - omegaVar;
    dfloat tt_omegaVar = 1 - omegaVar/2;
    dfloat omegaVar_d2 = omegaVar / 2;
    dfloat tt_omega_t3 = tt_omegaVar * 3;
    #else
    dfloat omegaVar = OMEGA;
    #endif

    #ifdef SECOND_DIST 
        dfloat cVar     = G_M_0_SCALE *fMom[idxMom(threadIdx.x, threadIdx.y, threadIdx.z, M_C_INDEX, blockIdx.x, blockIdx.y, blockIdx.z)];
        dfloat cx_t30   = ux_t30;
        dfloat cy_t30   = uy_t30;
        dfloat cz_t30   = uz_t30;

        #include "includeFiles/g_popReconstruction"

        __syncthreads();

        //overwrite values
        s_pop[idxPopBlock(threadIdx.x, threadIdx.y, threadIdx.z,  0)] = gNode[ 1];
        s_pop[idxPopBlock(threadIdx.x, threadIdx.y, threadIdx.z,  1)] = gNode[ 2];
        s_pop[idxPopBlock(threadIdx.x, threadIdx.y, threadIdx.z,  2)] = gNode[ 3];
        s_pop[idxPopBlock(threadIdx.x, threadIdx.y, threadIdx.z,  3)] = gNode[ 4];
        s_pop[idxPopBlock(threadIdx.x, threadIdx.y, threadIdx.z,  4)] = gNode[ 5];
        s_pop[idxPopBlock(threadIdx.x, threadIdx.y, threadIdx.z,  5)] = gNode[ 6];
        s_pop[idxPopBlock(threadIdx.x, threadIdx.y, threadIdx.z,  6)] = gNode[ 7];
        s_pop[idxPopBlock(threadIdx.x, threadIdx.y, threadIdx.z,  7)] = gNode[ 8];
        s_pop[idxPopBlock(threadIdx.x, threadIdx.y, threadIdx.z,  8)] = gNode[ 9];
        s_pop[idxPopBlock(threadIdx.x, threadIdx.y, threadIdx.z,  9)] = gNode[10];
        s_pop[idxPopBlock(threadIdx.x, threadIdx.y, threadIdx.z, 10)] = gNode[11];
        s_pop[idxPopBlock(threadIdx.x, threadIdx.y, threadIdx.z, 11)] = gNode[12];
        s_pop[idxPopBlock(threadIdx.x, threadIdx.y, threadIdx.z, 12)] = gNode[13];
        s_pop[idxPopBlock(threadIdx.x, threadIdx.y, threadIdx.z, 13)] = gNode[14];
        s_pop[idxPopBlock(threadIdx.x, threadIdx.y, threadIdx.z, 14)] = gNode[15];
        s_pop[idxPopBlock(threadIdx.x, threadIdx.y, threadIdx.z, 15)] = gNode[16];
        s_pop[idxPopBlock(threadIdx.x, threadIdx.y, threadIdx.z, 16)] = gNode[17];
        s_pop[idxPopBlock(threadIdx.x, threadIdx.y, threadIdx.z, 17)] = gNode[18];

        
        //sync threads of the block so all populations are saved
        __syncthreads();

        /* pull */
        gNode[ 1] = s_pop[idxPopBlock(xm1, threadIdx.y, threadIdx.z, 0)];
        gNode[ 2] = s_pop[idxPopBlock(xp1, threadIdx.y, threadIdx.z, 1)];
        gNode[ 3] = s_pop[idxPopBlock(threadIdx.x, ym1, threadIdx.z, 2)];
        gNode[ 4] = s_pop[idxPopBlock(threadIdx.x, yp1, threadIdx.z, 3)];
        gNode[ 5] = s_pop[idxPopBlock(threadIdx.x, threadIdx.y, zm1, 4)];
        gNode[ 6] = s_pop[idxPopBlock(threadIdx.x, threadIdx.y, zp1, 5)];
        gNode[ 7] = s_pop[idxPopBlock(xm1, ym1, threadIdx.z, 6)];
        gNode[ 8] = s_pop[idxPopBlock(xp1, yp1, threadIdx.z, 7)];
        gNode[ 9] = s_pop[idxPopBlock(xm1, threadIdx.y, zm1, 8)];
        gNode[10] = s_pop[idxPopBlock(xp1, threadIdx.y, zp1, 9)];
        gNode[11] = s_pop[idxPopBlock(threadIdx.x, ym1, zm1, 10)];
        gNode[12] = s_pop[idxPopBlock(threadIdx.x, yp1, zp1, 11)];
        gNode[13] = s_pop[idxPopBlock(xm1, yp1, threadIdx.z, 12)];
        gNode[14] = s_pop[idxPopBlock(xp1, ym1, threadIdx.z, 13)];
        gNode[15] = s_pop[idxPopBlock(xm1, threadIdx.y, zp1, 14)];
        gNode[16] = s_pop[idxPopBlock(xp1, threadIdx.y, zm1, 15)];
        gNode[17] = s_pop[idxPopBlock(threadIdx.x, ym1, zp1, 16)];
        gNode[18] = s_pop[idxPopBlock(threadIdx.x, yp1, zm1, 17)];
                
        #include "includeFiles/g_popLoad"

        dfloat invC;

        if(nodeType != BULK){
            #include BC_SECONDARY_PATH
        }
        cVar = gNode[0] + gNode[1] + gNode[2] + gNode[3] + gNode[4] + gNode[5] + gNode[6] + gNode[7] + gNode[8] + gNode[9] + gNode[10] + gNode[11] + gNode[12] + gNode[13] + gNode[14] + gNode[15] + gNode[16] + gNode[17] + gNode[18];
        invC= 1.0/cVar;

        #include "includeFiles/g_popReconstruction"

        #include "includeFiles/g_popSave"
        fMom[idxMom(threadIdx.x, threadIdx.y, threadIdx.z, M_C_INDEX, blockIdx.x, blockIdx.y, blockIdx.z)] = cVar;
    #endif

    //Local forces
    dfloat L_Fx = FX;
    dfloat L_Fy = FY;
    dfloat L_Fz = FZ;

    #ifdef BC_FORCES
    dfloat L_BC_Fx = 0.0;
    dfloat L_BC_Fy = 0.0;
    dfloat L_BC_Fz = 0.0;
    #endif


    #ifndef HIGH_ORDER_COLLISION

        #include "includeFiles/popReconstruction"
    #endif //!HIGH_ORDER_COLLISION
    #ifdef HIGH_ORDER_COLLISION
            #ifdef HOME_LBM
            multiplyTerm = rhoVar * W0;
            pics2 = 1.0 - cs2 * (m_xx_t45 + m_yy_t45 + m_zz_t45);

            pop[ 0] = multiplyTerm * (pics2);
            multiplyTerm = rhoVar * W1;
            pop[ 1] = multiplyTerm * (pics2 + ux_t30 + m_xx_t45 + (ux_t30*uy_t30*uy_t30)/3 - (m_zz_t45*ux_t30)/3 - (m_xy_t90*uy_t30)/3 - (m_xz_t90*uz_t30)/3 - (m_yy_t45*ux_t30)/3 + (ux_t30*uz_t30*uz_t30)/3);
            pop[ 2] = multiplyTerm * (pics2 - ux_t30 + m_xx_t45 + (m_yy_t45*ux_t30)/3 + (m_zz_t45*ux_t30)/3 + (m_xy_t90*uy_t30)/3 + (m_xz_t90*uz_t30)/3 - (ux_t30*uy_t30*uy_t30)/3 - (ux_t30*uz_t30*uz_t30)/3);
            pop[ 3] = multiplyTerm * (pics2 + uy_t30 + m_yy_t45 + (ux_t30*ux_t30*uy_t30)/3 - (m_xx_t45*uy_t30)/3 - (m_zz_t45*uy_t30)/3 - (m_yz_t90*uz_t30)/3 - (m_xy_t90*ux_t30)/3 + (uy_t30*uz_t30*uz_t30)/3);
            pop[ 4] = multiplyTerm * (pics2 - uy_t30 + m_yy_t45 + (m_xy_t90*ux_t30)/3 + (m_xx_t45*uy_t30)/3 + (m_zz_t45*uy_t30)/3 + (m_yz_t90*uz_t30)/3 - (ux_t30*ux_t30*uy_t30)/3 - (uy_t30*uz_t30*uz_t30)/3);
            pop[ 5] = multiplyTerm * (pics2 + uz_t30 + m_zz_t45 + (ux_t30*ux_t30*uz_t30)/3 - (m_yz_t90*uy_t30)/3 - (m_xx_t45*uz_t30)/3 - (m_yy_t45*uz_t30)/3 - (m_xz_t90*ux_t30)/3 + (uy_t30*uy_t30*uz_t30)/3);
            pop[ 6] = multiplyTerm * (pics2 - uz_t30 + m_zz_t45 + (m_xz_t90*ux_t30)/3 + (m_yz_t90*uy_t30)/3 + (m_xx_t45*uz_t30)/3 + (m_yy_t45*uz_t30)/3 - (ux_t30*ux_t30*uz_t30)/3 - (uy_t30*uy_t30*uz_t30)/3);
            multiplyTerm = rhoVar * W2;
            pop[ 7] = multiplyTerm * (pics2 +ux_t30 + uy_t30 + m_xx_t45 + m_yy_t45 + m_xy_t90 + (2*m_xy_t90*ux_t30)/3 + (2*m_yy_t45*ux_t30)/3 - (m_zz_t45*ux_t30)/3 + (2*m_xx_t45*uy_t30)/3 + (2*m_xy_t90*uy_t30)/3 - (m_zz_t45*uy_t30)/3 - (m_xz_t90*uz_t30)/3 - (m_yz_t90*uz_t30)/3 - (2*ux_t30*uy_t30*uy_t30)/3 - (2*ux_t30*ux_t30*uy_t30)/3 + (ux_t30*uz_t30*uz_t30)/3 + (uy_t30*uz_t30*uz_t30)/3);
            pop[ 8] = multiplyTerm * (pics2 -ux_t30 + m_xx_t45 - uy_t30 + m_yy_t45 + m_xy_t90 + (m_zz_t45*ux_t30)/3 - (2*m_yy_t45*ux_t30)/3 - (2*m_xy_t90*ux_t30)/3 - (2*m_xx_t45*uy_t30)/3 - (2*m_xy_t90*uy_t30)/3 + (m_zz_t45*uy_t30)/3 + (m_xz_t90*uz_t30)/3 + (m_yz_t90*uz_t30)/3 + (2*ux_t30*uy_t30*uy_t30)/3 + (2*ux_t30*ux_t30*uy_t30)/3 - (ux_t30*uz_t30*uz_t30)/3 - (uy_t30*uz_t30*uz_t30)/3);
            pop[ 9] = multiplyTerm * (pics2 +ux_t30 + uz_t30 + m_xx_t45 + m_zz_t45 + m_xz_t90 + (2*m_xz_t90*ux_t30)/3 - (m_yy_t45*ux_t30)/3 + (2*m_zz_t45*ux_t30)/3 - (m_xy_t90*uy_t30)/3 - (m_yz_t90*uy_t30)/3 + (2*m_xx_t45*uz_t30)/3 + (2*m_xz_t90*uz_t30)/3 - (m_yy_t45*uz_t30)/3 + (ux_t30*uy_t30*uy_t30)/3 - (2*ux_t30*uz_t30*uz_t30)/3 - (2*ux_t30*ux_t30*uz_t30)/3 + (uy_t30*uy_t30*uz_t30)/3);
            pop[10] = multiplyTerm * (pics2 -ux_t30 + m_xx_t45 - uz_t30 + m_zz_t45 + m_xz_t90 + (m_yy_t45*ux_t30)/3 - (2*m_xz_t90*ux_t30)/3 - (2*m_zz_t45*ux_t30)/3 + (m_xy_t90*uy_t30)/3 + (m_yz_t90*uy_t30)/3 - (2*m_xx_t45*uz_t30)/3 - (2*m_xz_t90*uz_t30)/3 + (m_yy_t45*uz_t30)/3 - (ux_t30*uy_t30*uy_t30)/3 + (2*ux_t30*uz_t30*uz_t30)/3 + (2*ux_t30*ux_t30*uz_t30)/3 - (uy_t30*uy_t30*uz_t30)/3);
            pop[11] = multiplyTerm * (pics2 +uy_t30 + uz_t30 + m_yy_t45 + m_zz_t45 + m_yz_t90 + (2*m_yz_t90*uy_t30)/3 - (m_xz_t90*ux_t30)/3 - (m_xx_t45*uy_t30)/3 - (m_xy_t90*ux_t30)/3 + (2*m_zz_t45*uy_t30)/3 - (m_xx_t45*uz_t30)/3 + (2*m_yy_t45*uz_t30)/3 + (2*m_yz_t90*uz_t30)/3 + (ux_t30*ux_t30*uy_t30)/3 + (ux_t30*ux_t30*uz_t30)/3 - (2*uy_t30*uz_t30*uz_t30)/3 - (2*uy_t30*uy_t30*uz_t30)/3);
            pop[12] = multiplyTerm * (pics2 -uy_t30 + m_yy_t45 - uz_t30 + m_zz_t45 + m_yz_t90 + (m_xy_t90*ux_t30)/3 + (m_xz_t90*ux_t30)/3 + (m_xx_t45*uy_t30)/3 - (2*m_yz_t90*uy_t30)/3 - (2*m_zz_t45*uy_t30)/3 + (m_xx_t45*uz_t30)/3 - (2*m_yy_t45*uz_t30)/3 - (2*m_yz_t90*uz_t30)/3 - (ux_t30*ux_t30*uy_t30)/3 - (ux_t30*ux_t30*uz_t30)/3 + (2*uy_t30*uz_t30*uz_t30)/3 + (2*uy_t30*uy_t30*uz_t30)/3);
            pop[13] = multiplyTerm * (pics2 +ux_t30 - uy_t30 + m_xx_t45 + m_yy_t45 - m_xy_t90 + (2*m_yy_t45*ux_t30)/3 - (2*m_xy_t90*ux_t30)/3 - (m_zz_t45*ux_t30)/3 - (2*m_xx_t45*uy_t30)/3 + (2*m_xy_t90*uy_t30)/3 + (m_zz_t45*uy_t30)/3 - (m_xz_t90*uz_t30)/3 + (m_yz_t90*uz_t30)/3 - (2*ux_t30*uy_t30*uy_t30)/3 + (2*ux_t30*ux_t30*uy_t30)/3 + (ux_t30*uz_t30*uz_t30)/3 - (uy_t30*uz_t30*uz_t30)/3);
            pop[14] = multiplyTerm * (pics2 -ux_t30 + uy_t30 + m_xx_t45 + m_yy_t45 - m_xy_t90 + (2*m_xy_t90*ux_t30)/3 - (2*m_yy_t45*ux_t30)/3 + (m_zz_t45*ux_t30)/3 + (2*m_xx_t45*uy_t30)/3 - (2*m_xy_t90*uy_t30)/3 - (m_zz_t45*uy_t30)/3 + (m_xz_t90*uz_t30)/3 - (m_yz_t90*uz_t30)/3 + (2*ux_t30*uy_t30*uy_t30)/3 - (2*ux_t30*ux_t30*uy_t30)/3 - (ux_t30*uz_t30*uz_t30)/3 + (uy_t30*uz_t30*uz_t30)/3);
            pop[15] = multiplyTerm * (pics2 +ux_t30 - uz_t30 + m_xx_t45 + m_zz_t45 - m_xz_t90 + (2*m_zz_t45*ux_t30)/3 - (m_yy_t45*ux_t30)/3 - (2*m_xz_t90*ux_t30)/3 - (m_xy_t90*uy_t30)/3 + (m_yz_t90*uy_t30)/3 - (2*m_xx_t45*uz_t30)/3 + (2*m_xz_t90*uz_t30)/3 + (m_yy_t45*uz_t30)/3 + (ux_t30*uy_t30*uy_t30)/3 - (2*ux_t30*uz_t30*uz_t30)/3 + (2*ux_t30*ux_t30*uz_t30)/3 - (uy_t30*uy_t30*uz_t30)/3);
            pop[16] = multiplyTerm * (pics2 -ux_t30 + uz_t30 + m_xx_t45 + m_zz_t45 - m_xz_t90 + (2*m_xz_t90*ux_t30)/3 + (m_yy_t45*ux_t30)/3 - (2*m_zz_t45*ux_t30)/3 + (m_xy_t90*uy_t30)/3 - (m_yz_t90*uy_t30)/3 + (2*m_xx_t45*uz_t30)/3 - (2*m_xz_t90*uz_t30)/3 - (m_yy_t45*uz_t30)/3 - (ux_t30*uy_t30*uy_t30)/3 + (2*ux_t30*uz_t30*uz_t30)/3 - (2*ux_t30*ux_t30*uz_t30)/3 + (uy_t30*uy_t30*uz_t30)/3);
            pop[17] = multiplyTerm * (pics2 +uy_t30 - uz_t30 + m_yy_t45 + m_zz_t45 - m_yz_t90 + (m_xz_t90*ux_t30)/3 - (m_xy_t90*ux_t30)/3 - (m_xx_t45*uy_t30)/3 - (2*m_yz_t90*uy_t30)/3 + (2*m_zz_t45*uy_t30)/3 + (m_xx_t45*uz_t30)/3 - (2*m_yy_t45*uz_t30)/3 + (2*m_yz_t90*uz_t30)/3 + (ux_t30*ux_t30*uy_t30)/3 - (ux_t30*ux_t30*uz_t30)/3 - (2*uy_t30*uz_t30*uz_t30)/3 + (2*uy_t30*uy_t30*uz_t30)/3);
            pop[18] = multiplyTerm * (pics2 -uy_t30 + uz_t30 + m_yy_t45 + m_zz_t45 - m_yz_t90 + (m_xy_t90*ux_t30)/3 - (m_xz_t90*ux_t30)/3 + (m_xx_t45*uy_t30)/3 + (2*m_yz_t90*uy_t30)/3 - (2*m_zz_t45*uy_t30)/3 - (m_xx_t45*uz_t30)/3 + (2*m_yy_t45*uz_t30)/3 - (2*m_yz_t90*uz_t30)/3 - (ux_t30*ux_t30*uy_t30)/3 + (ux_t30*ux_t30*uz_t30)/3 + (2*uy_t30*uz_t30*uz_t30)/3 - (2*uy_t30*uy_t30*uz_t30)/3);
           #endif
    #endif //HIGH_ORDER_COLLISION


    //save populations in shared memory
    s_pop[idxPopBlock(threadIdx.x, threadIdx.y, threadIdx.z,  0)] = pop[ 1];
    s_pop[idxPopBlock(threadIdx.x, threadIdx.y, threadIdx.z,  1)] = pop[ 2];
    s_pop[idxPopBlock(threadIdx.x, threadIdx.y, threadIdx.z,  2)] = pop[ 3];
    s_pop[idxPopBlock(threadIdx.x, threadIdx.y, threadIdx.z,  3)] = pop[ 4];
    s_pop[idxPopBlock(threadIdx.x, threadIdx.y, threadIdx.z,  4)] = pop[ 5];
    s_pop[idxPopBlock(threadIdx.x, threadIdx.y, threadIdx.z,  5)] = pop[ 6];
    s_pop[idxPopBlock(threadIdx.x, threadIdx.y, threadIdx.z,  6)] = pop[ 7];
    s_pop[idxPopBlock(threadIdx.x, threadIdx.y, threadIdx.z,  7)] = pop[ 8];
    s_pop[idxPopBlock(threadIdx.x, threadIdx.y, threadIdx.z,  8)] = pop[ 9];
    s_pop[idxPopBlock(threadIdx.x, threadIdx.y, threadIdx.z,  9)] = pop[10];
    s_pop[idxPopBlock(threadIdx.x, threadIdx.y, threadIdx.z, 10)] = pop[11];
    s_pop[idxPopBlock(threadIdx.x, threadIdx.y, threadIdx.z, 11)] = pop[12];
    s_pop[idxPopBlock(threadIdx.x, threadIdx.y, threadIdx.z, 12)] = pop[13];
    s_pop[idxPopBlock(threadIdx.x, threadIdx.y, threadIdx.z, 13)] = pop[14];
    s_pop[idxPopBlock(threadIdx.x, threadIdx.y, threadIdx.z, 14)] = pop[15];
    s_pop[idxPopBlock(threadIdx.x, threadIdx.y, threadIdx.z, 15)] = pop[16];
    s_pop[idxPopBlock(threadIdx.x, threadIdx.y, threadIdx.z, 16)] = pop[17];
    s_pop[idxPopBlock(threadIdx.x, threadIdx.y, threadIdx.z, 17)] = pop[18];
    #ifdef D3Q27
    s_pop[idxPopBlock(threadIdx.x, threadIdx.y, threadIdx.z, 18)] = pop[19];
    s_pop[idxPopBlock(threadIdx.x, threadIdx.y, threadIdx.z, 19)] = pop[20];
    s_pop[idxPopBlock(threadIdx.x, threadIdx.y, threadIdx.z, 20)] = pop[21];
    s_pop[idxPopBlock(threadIdx.x, threadIdx.y, threadIdx.z, 21)] = pop[22];
    s_pop[idxPopBlock(threadIdx.x, threadIdx.y, threadIdx.z, 22)] = pop[23];
    s_pop[idxPopBlock(threadIdx.x, threadIdx.y, threadIdx.z, 23)] = pop[24];
    s_pop[idxPopBlock(threadIdx.x, threadIdx.y, threadIdx.z, 24)] = pop[25];
    s_pop[idxPopBlock(threadIdx.x, threadIdx.y, threadIdx.z, 25)] = pop[26];
    #endif //D3Q27

    //sync threads of the block so all populations are saved
    __syncthreads();

    /* pull */



    pop[ 1] = s_pop[idxPopBlock(xm1, threadIdx.y, threadIdx.z, 0)];
    pop[ 2] = s_pop[idxPopBlock(xp1, threadIdx.y, threadIdx.z, 1)];
    pop[ 3] = s_pop[idxPopBlock(threadIdx.x, ym1, threadIdx.z, 2)];
    pop[ 4] = s_pop[idxPopBlock(threadIdx.x, yp1, threadIdx.z, 3)];
    pop[ 5] = s_pop[idxPopBlock(threadIdx.x, threadIdx.y, zm1, 4)];
    pop[ 6] = s_pop[idxPopBlock(threadIdx.x, threadIdx.y, zp1, 5)];
    pop[ 7] = s_pop[idxPopBlock(xm1, ym1, threadIdx.z, 6)];
    pop[ 8] = s_pop[idxPopBlock(xp1, yp1, threadIdx.z, 7)];
    pop[ 9] = s_pop[idxPopBlock(xm1, threadIdx.y, zm1, 8)];
    pop[10] = s_pop[idxPopBlock(xp1, threadIdx.y, zp1, 9)];
    pop[11] = s_pop[idxPopBlock(threadIdx.x, ym1, zm1, 10)];
    pop[12] = s_pop[idxPopBlock(threadIdx.x, yp1, zp1, 11)];
    pop[13] = s_pop[idxPopBlock(xm1, yp1, threadIdx.z, 12)];
    pop[14] = s_pop[idxPopBlock(xp1, ym1, threadIdx.z, 13)];
    pop[15] = s_pop[idxPopBlock(xm1, threadIdx.y, zp1, 14)];
    pop[16] = s_pop[idxPopBlock(xp1, threadIdx.y, zm1, 15)];
    pop[17] = s_pop[idxPopBlock(threadIdx.x, ym1, zp1, 16)];
    pop[18] = s_pop[idxPopBlock(threadIdx.x, yp1, zm1, 17)];
    #ifdef D3Q27
    pop[19] = s_pop[idxPopBlock(xm1, ym1, zm1, 18)];
    pop[20] = s_pop[idxPopBlock(xp1, yp1, zp1, 19)];
    pop[21] = s_pop[idxPopBlock(xm1, ym1, zp1, 20)];
    pop[22] = s_pop[idxPopBlock(xp1, yp1, zm1, 21)];
    pop[23] = s_pop[idxPopBlock(xm1, yp1, zm1, 22)];
    pop[24] = s_pop[idxPopBlock(xp1, ym1, zp1, 23)];
    pop[25] = s_pop[idxPopBlock(xp1, ym1, zm1, 24)];
    pop[26] = s_pop[idxPopBlock(xm1, yp1, zp1, 25)];
    #endif

    /* load pop from global in cover nodes */

   



    #include "includeFiles/popLoad"



    #ifdef BC_MOMENT_BASED
        dfloat invRho;
        if(nodeType != BULK){
            #include BC_PATH

            invRho = 1.0 / rhoVar;               
        }else{

            //calculate streaming moments
            #ifdef D3Q19
                //equation3
                rhoVar = pop[0] + pop[1] + pop[2] + pop[3] + pop[4] + pop[5] + pop[6] + pop[7] + pop[8] + pop[9] + pop[10] + pop[11] + pop[12] + pop[13] + pop[14] + pop[15] + pop[16] + pop[17] + pop[18];
                invRho = 1 / rhoVar;
                //equation4 + force correction
                ux_t30 = ((pop[1] - pop[2] + pop[7] - pop[ 8] + pop[ 9] - pop[10] + pop[13] - pop[14] + pop[15] - pop[16]) + L_Fx/2) * invRho;
                uy_t30 = ((pop[3] - pop[4] + pop[7] - pop[ 8] + pop[11] - pop[12] + pop[14] - pop[13] + pop[17] - pop[18]) + L_Fy/2) * invRho;
                uz_t30 = ((pop[5] - pop[6] + pop[9] - pop[10] + pop[11] - pop[12] + pop[16] - pop[15] + pop[18] - pop[17]) + L_Fz/2) * invRho;

                //equation5
                m_xx_t45 = (pop[1] + pop[2] + pop[7] + pop[8] + pop[9] + pop[10] + pop[13] + pop[14] + pop[15] + pop[16])* invRho - cs2;
                m_xy_t90 = (pop[7] - pop[13] + pop[8] - pop[14])* invRho;
                m_xz_t90 = (pop[9] - pop[15] + pop[10] - pop[16])* invRho;
                m_yy_t45 = (pop[3] + pop[4] + pop[7] + pop[8] + pop[11] + pop[12] + pop[13] + pop[14] + pop[17] + pop[18])* invRho - cs2;
                m_yz_t90 = (pop[11] - pop[17] + pop[12] - pop[18])* invRho;
                m_zz_t45 = (pop[5] + pop[6] + pop[9] + pop[10] + pop[11] + pop[12] + pop[15] + pop[16] + pop[17] + pop[18])* invRho - cs2;


            #endif
            #ifdef D3Q27
                rhoVar = pop[0] + pop[1] + pop[2] + pop[3] + pop[4] + pop[5] + pop[6] + pop[7] + pop[8] + pop[9] + pop[10] + pop[11] + pop[12] + pop[13] + pop[14] + pop[15] + pop[16] + pop[17] + pop[18] + pop[19] + pop[20] + pop[21] + pop[22] + pop[23] + pop[24] + pop[25] + pop[26];
                invRho = 1 / rhoVar;
                ux_t30 = ((pop[1] + pop[7] + pop[9] + pop[13] + pop[15] + pop[19] + pop[21] + pop[23] + pop[26])  - (pop[ 2] + pop[ 8] + pop[10] + pop[14] + pop[16] + pop[20] + pop[22] + pop[24] + pop[25]) + 0.5 * L_Fx) * invRho;
                uy_t30 = ((pop[3] + pop[7] + pop[11] + pop[14] + pop[17] + pop[19] + pop[21] + pop[24] + pop[25]) - (pop[ 4] + pop[ 8] + pop[12] + pop[13] + pop[18] + pop[20] + pop[22] + pop[23] + pop[26]) + 0.5 * L_Fy) * invRho;
                uz_t30 = ((pop[5] + pop[9] + pop[11] + pop[16] + pop[18] + pop[19] + pop[22] + pop[23] + pop[25]) - (pop[ 6] + pop[10] + pop[12] + pop[15] + pop[17] + pop[20] + pop[21] + pop[24] + pop[26]) + 0.5 * L_Fz) * invRho;

                m_xx_t45 = ( (pop[ 1] + pop[ 2] + pop[ 7] + pop[ 8] + pop[ 9] + pop[10]  +  pop[13] + pop[14] + pop[15] + pop[16] + pop[19] + pop[20] + pop[21] + pop[22] + pop[23] + pop[24] + pop[25] + pop[26]))* invRho - cs2;
                m_xy_t90 = (((pop[ 7] + pop[ 8] + pop[19] + pop[20] + pop[21] + pop[22]) - (pop[13] + pop[14] + pop[23] + pop[24] + pop[25] + pop[26])) )* invRho;
                m_xz_t90 = (((pop[ 9] + pop[10] + pop[19] + pop[20] + pop[23] + pop[24]) - (pop[15] + pop[16] + pop[21] + pop[22] + pop[25] + pop[26])) )* invRho;
                m_yy_t45 = ( (pop[ 3] + pop[ 4] + pop[ 7] + pop[ 8] + pop[11] + pop[12]  +  pop[13] + pop[14] + pop[17] + pop[18] + pop[19] + pop[20] + pop[21] + pop[22] + pop[23] + pop[24] + pop[25] + pop[26]))* invRho - cs2;
                m_yz_t90 = (((pop[11] + pop[12] + pop[19] + pop[20] + pop[25] + pop[26]) - (pop[17] + pop[18] + pop[21] + pop[22] + pop[23] + pop[24])))* invRho;
                m_zz_t45 = ( (pop[ 5] + pop[ 6] + pop[ 9] + pop[10] + pop[11] + pop[12]  +  pop[15] + pop[16] + pop[17] + pop[18] + pop[19] + pop[20] + pop[21] + pop[22] + pop[23] + pop[24] + pop[25] + pop[26]))* invRho - cs2;
            #endif
        }
    #endif // BC_MOMENT_BASED


    // MOMENTS DETERMINED, COMPUTE OMEGA IF NON-NEWTONIAN FLUID
    #if defined(NON_NEWTONIAN_FLUID) || defined(LES_MODEL)

    const dfloat S_XX = rhoVar * (m_xx_t45 - ux_t30*ux_t30);
    const dfloat S_YY = rhoVar * (m_yy_t45 - uy_t30*uy_t30);
    const dfloat S_ZZ = rhoVar * (m_zz_t45 - uz_t30*uz_t30);
    const dfloat S_XY = rhoVar * (m_xy_t90 - ux_t30*uy_t30);
    const dfloat S_XZ = rhoVar * (m_xz_t90 - ux_t30*uz_t30);
    const dfloat S_YZ = rhoVar * (m_yz_t90 - uy_t30*uz_t30);

    const dfloat uFxxd2 = ux_t30*L_Fx; // d2 = uFxx Divided by two
    const dfloat uFyyd2 = uy_t30*L_Fy;
    const dfloat uFzzd2 = uz_t30*L_Fz;
    const dfloat uFxyd2 = (ux_t30*L_Fy + uy_t30*L_Fx) / 2;
    const dfloat uFxzd2 = (ux_t30*L_Fz + uz_t30*L_Fx) / 2;
    const dfloat uFyzd2 = (uy_t30*L_Fz + uz_t30*L_Fy) / 2;

    const dfloat auxStressMag = sqrt(0.5 * (
        (S_XX + uFxxd2) * (S_XX + uFxxd2) +(S_YY + uFyyd2) * (S_YY + uFyyd2) + (S_ZZ + uFzzd2) * (S_ZZ + uFzzd2) +
        2 * ((S_XY + uFxyd2) * (S_XY + uFxyd2) + (S_XZ + uFxzd2) * (S_XZ + uFxzd2) + (S_YZ + uFyzd2) * (S_YZ + uFyzd2))));
        #ifdef NON_NEWTONIAN_FLUID
            /*
            dfloat eta = (1.0/omegaVar - 0.5) / 3.0;
            dfloat gamma_dot = (1 - 0.5 * (omegaVar)) * auxStressMag / eta;
            eta = VISC + S_Y/gamma_dot;
            omegaVar = omegaVar;// 1.0 / (0.5 + 3.0 * eta);
            */

            omegaVar = calcOmega(omegaVar, auxStressMag);
            #endif//  NON_NEWTONIAN_FLUID
        #ifdef LES_MODEL
            dfloat tau_t = 0.5*sqrt(TAU*TAU+Implicit_const*auxStressMag)-0.5*TAU;
            dfloat visc_turb_var = tau_t/3.0;

            omegaVar = 1.0/(TAU + tau_t);
        #endif
            t_omegaVar = 1 - omegaVar;
            tt_omegaVar = 1 - 0.5*omegaVar;
            omegaVar_d2 = omegaVar / 2.0;
            tt_omega_t3 = tt_omegaVar * 3.0;
    #endif 

    // COLLIDE

    //Collide Moments
    // multiply moments by as2 -- as4*0.5 -- as4 - add correction to m_alpha_beta
    #ifndef HIGH_ORDER_COLLISION
        ux_t30 = F_M_I_SCALE * ux_t30;
        uy_t30 = F_M_I_SCALE * uy_t30;
        uz_t30 = F_M_I_SCALE * uz_t30;

        m_xx_t45 = F_M_II_SCALE * (m_xx_t45);
        m_xy_t90 = F_M_IJ_SCALE * (m_xy_t90);
        m_xz_t90 = F_M_IJ_SCALE * (m_xz_t90);
        m_yy_t45 = F_M_II_SCALE * (m_yy_t45);
        m_yz_t90 = F_M_IJ_SCALE * (m_yz_t90);
        m_zz_t45 = F_M_II_SCALE * (m_zz_t45);

        #ifdef DENSITY_CORRECTION
            //printf("%f ",d_mean_rho[0]-1.0) ;
            rhoVar -= (d_mean_rho[0]-1e-7) ;
            invRho = 1/rhoVar;
        #endif // DENSITY_CORRECTION
        #if defined(NON_NEWTONIAN_FLUID) || defined(LES_MODEL)
            dfloat invRho_mt15 = -3*invRho/2;
            ux_t30 = (t_omegaVar * (ux_t30 + invRho_mt15 * L_Fx ) + omegaVar * ux_t30 + tt_omega_t3 * L_Fx);
            uy_t30 = (t_omegaVar * (uy_t30 + invRho_mt15 * L_Fy ) + omegaVar * uy_t30 + tt_omega_t3 * L_Fy);
            uz_t30 = (t_omegaVar * (uz_t30 + invRho_mt15 * L_Fz ) + omegaVar * uz_t30 + tt_omega_t3 * L_Fz);
            
            //equation 90
            m_xx_t45 = (t_omegaVar * m_xx_t45  +   omegaVar_d2 * ux_t30 * ux_t30  - invRho_mt15 * tt_omegaVar * (L_Fx * ux_t30 + L_Fx * ux_t30));
            m_yy_t45 = (t_omegaVar * m_yy_t45  +   omegaVar_d2 * uy_t30 * uy_t30  - invRho_mt15 * tt_omegaVar * (L_Fy * uy_t30 + L_Fy * uy_t30));
            m_zz_t45 = (t_omegaVar * m_zz_t45  +   omegaVar_d2 * uz_t30 * uz_t30  - invRho_mt15 * tt_omegaVar * (L_Fz * uz_t30 + L_Fz * uz_t30));

            m_xy_t90 = (t_omegaVar * m_xy_t90  +   omegaVar * ux_t30 * uy_t30    +    tt_omega_t3 *invRho* (L_Fx * uy_t30 + L_Fy * ux_t30));
            m_xz_t90 = (t_omegaVar * m_xz_t90  +   omegaVar * ux_t30 * uz_t30    +    tt_omega_t3 *invRho* (L_Fx * uz_t30 + L_Fz * ux_t30));
            m_yz_t90 = (t_omegaVar * m_yz_t90  +   omegaVar * uy_t30 * uz_t30    +    tt_omega_t3 *invRho* (L_Fy * uz_t30 + L_Fz * uy_t30));
        #endif // NON_NEWTONIAN_FLUID
        #if !(defined(NON_NEWTONIAN_FLUID) || defined(LES_MODEL))
            dfloat invRho_mt15 = as2*invRho/2;

            #ifdef THERMAL_MODEL //Boussinesq Approximation
                if(nodeType == BULK && T_BOUYANCY)
                    L_Fy += T_gravity_t_beta * RHO_0*((cVar-T_REFERENCE));
            #endif

            ux_t30 = ux_t30 + invRho_mt15 * L_Fx;
            uy_t30 = uy_t30 + invRho_mt15 * L_Fy;
            uz_t30 = uz_t30 + invRho_mt15 * L_Fz;
            
            //equation 90
            m_xx_t45 = (T_OMEGA * m_xx_t45  +   OMEGAd2 * ux_t30 * ux_t30    + invRho_mt15 * TT_OMEGA * (L_Fx * ux_t30 + L_Fx * ux_t30));
            m_yy_t45 = (T_OMEGA * m_yy_t45  +   OMEGAd2 * uy_t30 * uy_t30    + invRho_mt15 * TT_OMEGA * (L_Fy * uy_t30 + L_Fy * uy_t30));
            m_zz_t45 = (T_OMEGA * m_zz_t45  +   OMEGAd2 * uz_t30 * uz_t30    + invRho_mt15 * TT_OMEGA * (L_Fz * uz_t30 + L_Fz * uz_t30));

            m_xy_t90 = (T_OMEGA * m_xy_t90  +     OMEGA * ux_t30 * uy_t30    +    TT_OMEGA_T3 *invRho* (L_Fx * uy_t30 + L_Fy * ux_t30));
            m_xz_t90 = (T_OMEGA * m_xz_t90  +     OMEGA * ux_t30 * uz_t30    +    TT_OMEGA_T3 *invRho* (L_Fx * uz_t30 + L_Fz * ux_t30));
            m_yz_t90 = (T_OMEGA * m_yz_t90  +     OMEGA * uy_t30 * uz_t30    +    TT_OMEGA_T3 *invRho* (L_Fy * uz_t30 + L_Fz * uy_t30));
        #endif //!_NON_NEWTONIAN_FLUID
    #endif //!_HIGH_ORDER_COLLISION

    //USING HIGH
    #ifdef HIGH_ORDER_COLLISION

    #ifdef HO_RR

        dfloat ux = ux_t30 + L_Fx*invRho/2;
        dfloat uy = uy_t30 + L_Fy*invRho/2;
        dfloat uz = uz_t30 + L_Fz*invRho/2;

        //matlab original
        dfloat m_xx = (ux_t30*ux_t30 - (9*uy_t30*uy_t30*uz_t30*uz_t30)/2 + (3*m_zz_t45*uy_t30*uy_t30)/4 + 3*m_yz_t90*uy_t30*uz_t30 + (3*m_yy_t45*uz_t30*uz_t30)/4 - m_xx_t45)*omegaVar + ((15*uy_t30*uy_t30*uz_t30*uz_t30)/4 - (3*m_zz_t45*uy_t30*uy_t30)/4 - 3*m_yz_t90*uy_t30*uz_t30 - (3*m_yy_t45*uz_t30*uz_t30)/4 + m_xx_t45);
        dfloat m_yy = ((3*m_zz_t45*ux_t30*ux_t30)/4 - (9*ux_t30*ux_t30*uz_t30*uz_t30)/2 + 3*m_xz_t90*ux_t30*uz_t30 + uy_t30*uy_t30 + (3*m_xx_t45*uz_t30*uz_t30)/4 - m_yy_t45)*omegaVar + ((15*ux_t30*ux_t30*uz_t30*uz_t30)/4 - (3*m_zz_t45*ux_t30*ux_t30)/4 - 3*m_xz_t90*ux_t30*uz_t30 - (3*m_xx_t45*uz_t30*uz_t30)/4 + m_yy_t45);
        dfloat m_zz = ((3*m_yy_t45*ux_t30*ux_t30)/4 - (9*ux_t30*ux_t30*uy_t30*uy_t30)/2 + 3*m_xy_t90*ux_t30*uy_t30 + (3*m_xx_t45*uy_t30*uy_t30)/4 + uz_t30*uz_t30 - m_zz_t45)*omegaVar + ((15*ux_t30*ux_t30*uy_t30*uy_t30)/4 - (3*m_yy_t45*ux_t30*ux_t30)/4 - 3*m_xy_t90*ux_t30*uy_t30 - (3*m_xx_t45*uy_t30*uy_t30)/4 + m_zz_t45);
        dfloat m_xy = (ux_t30*uy_t30 - m_xy_t90)*omegaVar + m_xy_t90;
        dfloat m_xz = (ux_t30*uz_t30 - m_xz_t90)*omegaVar + m_xz_t90;
        dfloat m_yz = (uy_t30*uz_t30 - m_yz_t90)*omegaVar + m_yz_t90;


        //dfloat m_xx = ((((m_zz_t45*uy_t30*uy_t30 + m_yy_t45*uz_t30*uz_t30) - 6*uy_t30*uy_t30*uz_t30*uz_t30)/4 + m_yz_t90*uy_t30*uz_t30)*3 + ux_t30*ux_t30 - m_xx_t45)*omegaVar + (((5*uy_t30*uy_t30*uz_t30*uz_t30 - m_zz_t45*uy_t30*uy_t30 - m_yy_t45*uz_t30*uz_t30)/4 - m_yz_t90*uy_t30*uz_t30)*3 + m_xx_t45);
        //dfloat m_yy = ((((m_zz_t45*ux_t30*ux_t30 + m_xx_t45*uz_t30*uz_t30) - 6*ux_t30*ux_t30*uz_t30*uz_t30)/4 + m_xz_t90*ux_t30*uz_t30)*3 + uy_t30*uy_t30 - m_yy_t45)*omegaVar + (((5*ux_t30*ux_t30*uz_t30*uz_t30 - m_zz_t45*ux_t30*ux_t30 - m_xx_t45*uz_t30*uz_t30)/4 - m_xz_t90*ux_t30*uz_t30)*3 + m_yy_t45);
        //dfloat m_zz = ((((m_yy_t45*ux_t30*ux_t30 + m_xx_t45*uy_t30*uy_t30) - 6*ux_t30*ux_t30*uy_t30*uy_t30)/4 + m_xy_t90*ux_t30*uy_t30)*3 + uz_t30*uz_t30 - m_zz_t45)*omegaVar + (((5*ux_t30*ux_t30*uy_t30*uy_t30 - m_yy_t45*ux_t30*ux_t30 - m_xx_t45*uy_t30*uy_t30)/4 - m_xy_t90*ux_t30*uy_t30)*3 + m_zz_t45);
        //dfloat m_xy = (ux_t30*uy_t30 - m_xy_t90)*omegaVar + m_xy_t90;
        //dfloat m_xz = (ux_t30*uz_t30 - m_xz_t90)*omegaVar + m_xz_t90;
        //dfloat m_yz = (uy_t30*uz_t30 - m_yz_t90)*omegaVar + m_yz_t90;
    #endif //HO_RR
    #ifdef HOME_LBM
        dfloat ux = ux_t30 + L_Fx*invRho/2;
        dfloat uy = uy_t30 + L_Fy*invRho/2;
        dfloat uz = uz_t30 + L_Fz*invRho/2;


        dfloat m_xy = T_OMEGA * m_xy_t90 + OMEGA*ux_t30*uy_t30 + TT_OMEGA * invRho * (L_Fx * uy_t30 + L_Fy * ux_t30);
        dfloat m_xz = T_OMEGA * m_xz_t90 + OMEGA*ux_t30*uz_t30 + TT_OMEGA * invRho * (L_Fx * uz_t30 + L_Fz * ux_t30);
        dfloat m_yz = T_OMEGA * m_yz_t90 + OMEGA*uy_t30*uz_t30 + TT_OMEGA * invRho * (L_Fy * uz_t30 + L_Fz * uy_t30);

        dfloat m_xx = ONETHIRD* (T_OMEGA * (2*m_xx_t45 - m_yy_t45 - m_zz_t45) +  (ux_t30*ux_t30 + uy_t30*uy_t30 + uz_t30*uz_t30) + OMEGA*(2*ux_t30*ux_t30 - uy_t30*uy_t30 - uz_t30*uz_t30) + invRho*T_OMEGA*(L_Fx*ux_t30*2 - L_Fy*uy_t30 - L_Fz*uz_t30)) + invRho*L_Fx*ux_t30;
        dfloat m_yy = ONETHIRD* (T_OMEGA * (2*m_yy_t45 - m_xx_t45 - m_zz_t45) +  (ux_t30*ux_t30 + uy_t30*uy_t30 + uz_t30*uz_t30) + OMEGA*(2*uy_t30*uy_t30 - ux_t30*ux_t30 - uz_t30*uz_t30) + invRho*T_OMEGA*(L_Fy*uy_t30*2 - L_Fx*ux_t30 - L_Fz*uz_t30)) + invRho*L_Fy*uy_t30;
        dfloat m_zz = ONETHIRD* (T_OMEGA * (2*m_zz_t45 - m_xx_t45 - m_yy_t45) +  (ux_t30*ux_t30 + uy_t30*uy_t30 + uz_t30*uz_t30) + OMEGA*(2*uz_t30*uz_t30 - ux_t30*ux_t30 - uy_t30*uy_t30) + invRho*T_OMEGA*(L_Fz*uz_t30*2 - L_Fx*ux_t30 - L_Fy*uy_t30)) + invRho*L_Fz*uz_t30;
    #endif
    ux_t30 = 3 * ux;
    uy_t30 = 3 * uy;
    uz_t30 = 3 * uz;

    m_xx_t45 = 9*(m_xx)/2;
    m_xy_t90 = 9*(m_xy);
    m_xz_t90 = 9*(m_xz);
    m_yy_t45 = 9*(m_yy)/2;
    m_yz_t90 = 9*(m_yz);
    m_zz_t45 = 9*(m_zz)/2;



    #endif //HIGH_ORDER_COLLISION





    //calculate post collision populations
    #ifndef HIGH_ORDER_COLLISION
        #include "includeFiles/popReconstruction"
    #endif //!HIGH_ORDER_COLLISION
    #ifdef HIGH_ORDER_COLLISION
    
        #ifdef HOME_LBM
    multiplyTerm = rhoVar * W0;
    pics2 = 1.0 - cs2 * (m_xx_t45 + m_yy_t45 + m_zz_t45);

    pop[ 0] = multiplyTerm * (pics2);
    multiplyTerm = rhoVar * W1;
    pop[ 1] = multiplyTerm * (pics2 + ux_t30 + m_xx_t45 + (ux_t30*uy_t30*uy_t30)/3 - (m_zz_t45*ux_t30)/3 - (m_xy_t90*uy_t30)/3 - (m_xz_t90*uz_t30)/3 - (m_yy_t45*ux_t30)/3 + (ux_t30*uz_t30*uz_t30)/3);
    pop[ 2] = multiplyTerm * (pics2 - ux_t30 + m_xx_t45 + (m_yy_t45*ux_t30)/3 + (m_zz_t45*ux_t30)/3 + (m_xy_t90*uy_t30)/3 + (m_xz_t90*uz_t30)/3 - (ux_t30*uy_t30*uy_t30)/3 - (ux_t30*uz_t30*uz_t30)/3);
    pop[ 3] = multiplyTerm * (pics2 + uy_t30 + m_yy_t45 + (ux_t30*ux_t30*uy_t30)/3 - (m_xx_t45*uy_t30)/3 - (m_zz_t45*uy_t30)/3 - (m_yz_t90*uz_t30)/3 - (m_xy_t90*ux_t30)/3 + (uy_t30*uz_t30*uz_t30)/3);
    pop[ 4] = multiplyTerm * (pics2 - uy_t30 + m_yy_t45 + (m_xy_t90*ux_t30)/3 + (m_xx_t45*uy_t30)/3 + (m_zz_t45*uy_t30)/3 + (m_yz_t90*uz_t30)/3 - (ux_t30*ux_t30*uy_t30)/3 - (uy_t30*uz_t30*uz_t30)/3);
    pop[ 5] = multiplyTerm * (pics2 + uz_t30 + m_zz_t45 + (ux_t30*ux_t30*uz_t30)/3 - (m_yz_t90*uy_t30)/3 - (m_xx_t45*uz_t30)/3 - (m_yy_t45*uz_t30)/3 - (m_xz_t90*ux_t30)/3 + (uy_t30*uy_t30*uz_t30)/3);
    pop[ 6] = multiplyTerm * (pics2 - uz_t30 + m_zz_t45 + (m_xz_t90*ux_t30)/3 + (m_yz_t90*uy_t30)/3 + (m_xx_t45*uz_t30)/3 + (m_yy_t45*uz_t30)/3 - (ux_t30*ux_t30*uz_t30)/3 - (uy_t30*uy_t30*uz_t30)/3);
    
    multiplyTerm = rhoVar * W2;
    pop[ 7] = multiplyTerm * (pics2 +ux_t30 + uy_t30 + m_xx_t45 + m_yy_t45 + m_xy_t90 + (2*m_xy_t90*ux_t30)/3 + (2*m_yy_t45*ux_t30)/3 - (m_zz_t45*ux_t30)/3 + (2*m_xx_t45*uy_t30)/3 + (2*m_xy_t90*uy_t30)/3 - (m_zz_t45*uy_t30)/3 - (m_xz_t90*uz_t30)/3 - (m_yz_t90*uz_t30)/3 - (2*ux_t30*uy_t30*uy_t30)/3 - (2*ux_t30*ux_t30*uy_t30)/3 + (ux_t30*uz_t30*uz_t30)/3 + (uy_t30*uz_t30*uz_t30)/3);
    pop[ 8] = multiplyTerm * (pics2 -ux_t30 + m_xx_t45 - uy_t30 + m_yy_t45 + m_xy_t90 + (m_zz_t45*ux_t30)/3 - (2*m_yy_t45*ux_t30)/3 - (2*m_xy_t90*ux_t30)/3 - (2*m_xx_t45*uy_t30)/3 - (2*m_xy_t90*uy_t30)/3 + (m_zz_t45*uy_t30)/3 + (m_xz_t90*uz_t30)/3 + (m_yz_t90*uz_t30)/3 + (2*ux_t30*uy_t30*uy_t30)/3 + (2*ux_t30*ux_t30*uy_t30)/3 - (ux_t30*uz_t30*uz_t30)/3 - (uy_t30*uz_t30*uz_t30)/3);
    pop[ 9] = multiplyTerm * (pics2 +ux_t30 + uz_t30 + m_xx_t45 + m_zz_t45 + m_xz_t90 + (2*m_xz_t90*ux_t30)/3 - (m_yy_t45*ux_t30)/3 + (2*m_zz_t45*ux_t30)/3 - (m_xy_t90*uy_t30)/3 - (m_yz_t90*uy_t30)/3 + (2*m_xx_t45*uz_t30)/3 + (2*m_xz_t90*uz_t30)/3 - (m_yy_t45*uz_t30)/3 + (ux_t30*uy_t30*uy_t30)/3 - (2*ux_t30*uz_t30*uz_t30)/3 - (2*ux_t30*ux_t30*uz_t30)/3 + (uy_t30*uy_t30*uz_t30)/3);
    pop[10] = multiplyTerm * (pics2 -ux_t30 + m_xx_t45 - uz_t30 + m_zz_t45 + m_xz_t90 + (m_yy_t45*ux_t30)/3 - (2*m_xz_t90*ux_t30)/3 - (2*m_zz_t45*ux_t30)/3 + (m_xy_t90*uy_t30)/3 + (m_yz_t90*uy_t30)/3 - (2*m_xx_t45*uz_t30)/3 - (2*m_xz_t90*uz_t30)/3 + (m_yy_t45*uz_t30)/3 - (ux_t30*uy_t30*uy_t30)/3 + (2*ux_t30*uz_t30*uz_t30)/3 + (2*ux_t30*ux_t30*uz_t30)/3 - (uy_t30*uy_t30*uz_t30)/3);
    pop[11] = multiplyTerm * (pics2 +uy_t30 + uz_t30 + m_yy_t45 + m_zz_t45 + m_yz_t90 + (2*m_yz_t90*uy_t30)/3 - (m_xz_t90*ux_t30)/3 - (m_xx_t45*uy_t30)/3 - (m_xy_t90*ux_t30)/3 + (2*m_zz_t45*uy_t30)/3 - (m_xx_t45*uz_t30)/3 + (2*m_yy_t45*uz_t30)/3 + (2*m_yz_t90*uz_t30)/3 + (ux_t30*ux_t30*uy_t30)/3 + (ux_t30*ux_t30*uz_t30)/3 - (2*uy_t30*uz_t30*uz_t30)/3 - (2*uy_t30*uy_t30*uz_t30)/3);
    pop[12] = multiplyTerm * (pics2 -uy_t30 + m_yy_t45 - uz_t30 + m_zz_t45 + m_yz_t90 + (m_xy_t90*ux_t30)/3 + (m_xz_t90*ux_t30)/3 + (m_xx_t45*uy_t30)/3 - (2*m_yz_t90*uy_t30)/3 - (2*m_zz_t45*uy_t30)/3 + (m_xx_t45*uz_t30)/3 - (2*m_yy_t45*uz_t30)/3 - (2*m_yz_t90*uz_t30)/3 - (ux_t30*ux_t30*uy_t30)/3 - (ux_t30*ux_t30*uz_t30)/3 + (2*uy_t30*uz_t30*uz_t30)/3 + (2*uy_t30*uy_t30*uz_t30)/3);
    pop[13] = multiplyTerm * (pics2 +ux_t30 - uy_t30 + m_xx_t45 + m_yy_t45 - m_xy_t90 + (2*m_yy_t45*ux_t30)/3 - (2*m_xy_t90*ux_t30)/3 - (m_zz_t45*ux_t30)/3 - (2*m_xx_t45*uy_t30)/3 + (2*m_xy_t90*uy_t30)/3 + (m_zz_t45*uy_t30)/3 - (m_xz_t90*uz_t30)/3 + (m_yz_t90*uz_t30)/3 - (2*ux_t30*uy_t30*uy_t30)/3 + (2*ux_t30*ux_t30*uy_t30)/3 + (ux_t30*uz_t30*uz_t30)/3 - (uy_t30*uz_t30*uz_t30)/3);
    pop[14] = multiplyTerm * (pics2 -ux_t30 + uy_t30 + m_xx_t45 + m_yy_t45 - m_xy_t90 + (2*m_xy_t90*ux_t30)/3 - (2*m_yy_t45*ux_t30)/3 + (m_zz_t45*ux_t30)/3 + (2*m_xx_t45*uy_t30)/3 - (2*m_xy_t90*uy_t30)/3 - (m_zz_t45*uy_t30)/3 + (m_xz_t90*uz_t30)/3 - (m_yz_t90*uz_t30)/3 + (2*ux_t30*uy_t30*uy_t30)/3 - (2*ux_t30*ux_t30*uy_t30)/3 - (ux_t30*uz_t30*uz_t30)/3 + (uy_t30*uz_t30*uz_t30)/3);
    pop[15] = multiplyTerm * (pics2 +ux_t30 - uz_t30 + m_xx_t45 + m_zz_t45 - m_xz_t90 + (2*m_zz_t45*ux_t30)/3 - (m_yy_t45*ux_t30)/3 - (2*m_xz_t90*ux_t30)/3 - (m_xy_t90*uy_t30)/3 + (m_yz_t90*uy_t30)/3 - (2*m_xx_t45*uz_t30)/3 + (2*m_xz_t90*uz_t30)/3 + (m_yy_t45*uz_t30)/3 + (ux_t30*uy_t30*uy_t30)/3 - (2*ux_t30*uz_t30*uz_t30)/3 + (2*ux_t30*ux_t30*uz_t30)/3 - (uy_t30*uy_t30*uz_t30)/3);
    pop[16] = multiplyTerm * (pics2 -ux_t30 + uz_t30 + m_xx_t45 + m_zz_t45 - m_xz_t90 + (2*m_xz_t90*ux_t30)/3 + (m_yy_t45*ux_t30)/3 - (2*m_zz_t45*ux_t30)/3 + (m_xy_t90*uy_t30)/3 - (m_yz_t90*uy_t30)/3 + (2*m_xx_t45*uz_t30)/3 - (2*m_xz_t90*uz_t30)/3 - (m_yy_t45*uz_t30)/3 - (ux_t30*uy_t30*uy_t30)/3 + (2*ux_t30*uz_t30*uz_t30)/3 - (2*ux_t30*ux_t30*uz_t30)/3 + (uy_t30*uy_t30*uz_t30)/3);
    pop[17] = multiplyTerm * (pics2 +uy_t30 - uz_t30 + m_yy_t45 + m_zz_t45 - m_yz_t90 + (m_xz_t90*ux_t30)/3 - (m_xy_t90*ux_t30)/3 - (m_xx_t45*uy_t30)/3 - (2*m_yz_t90*uy_t30)/3 + (2*m_zz_t45*uy_t30)/3 + (m_xx_t45*uz_t30)/3 - (2*m_yy_t45*uz_t30)/3 + (2*m_yz_t90*uz_t30)/3 + (ux_t30*ux_t30*uy_t30)/3 - (ux_t30*ux_t30*uz_t30)/3 - (2*uy_t30*uz_t30*uz_t30)/3 + (2*uy_t30*uy_t30*uz_t30)/3);
    pop[18] = multiplyTerm * (pics2 -uy_t30 + uz_t30 + m_yy_t45 + m_zz_t45 - m_yz_t90 + (m_xy_t90*ux_t30)/3 - (m_xz_t90*ux_t30)/3 + (m_xx_t45*uy_t30)/3 + (2*m_yz_t90*uy_t30)/3 - (2*m_zz_t45*uy_t30)/3 - (m_xx_t45*uz_t30)/3 + (2*m_yy_t45*uz_t30)/3 - (2*m_yz_t90*uz_t30)/3 - (ux_t30*ux_t30*uy_t30)/3 + (ux_t30*ux_t30*uz_t30)/3 + (2*uy_t30*uz_t30*uz_t30)/3 - (2*uy_t30*uy_t30*uz_t30)/3);

        #endif
    #endif //HIGH_ORDER_COLLISION
    
    
    /* write to global mom */

    fMom[idxMom(threadIdx.x, threadIdx.y, threadIdx.z, M_RHO_INDEX, blockIdx.x, blockIdx.y, blockIdx.z)] = rhoVar - RHO_0;

    fMom[idxMom(threadIdx.x, threadIdx.y, threadIdx.z, M_UX_INDEX, blockIdx.x, blockIdx.y, blockIdx.z)] = ux_t30 / F_M_I_SCALE;
    fMom[idxMom(threadIdx.x, threadIdx.y, threadIdx.z, M_UY_INDEX, blockIdx.x, blockIdx.y, blockIdx.z)] = uy_t30 / F_M_I_SCALE;
    fMom[idxMom(threadIdx.x, threadIdx.y, threadIdx.z, M_UZ_INDEX, blockIdx.x, blockIdx.y, blockIdx.z)] = uz_t30 / F_M_I_SCALE;

    fMom[idxMom(threadIdx.x, threadIdx.y, threadIdx.z, M_MXX_INDEX, blockIdx.x, blockIdx.y, blockIdx.z)] = m_xx_t45 / F_M_II_SCALE;
    fMom[idxMom(threadIdx.x, threadIdx.y, threadIdx.z, M_MXY_INDEX, blockIdx.x, blockIdx.y, blockIdx.z)] = m_xy_t90 / F_M_IJ_SCALE;
    fMom[idxMom(threadIdx.x, threadIdx.y, threadIdx.z, M_MXZ_INDEX, blockIdx.x, blockIdx.y, blockIdx.z)] = m_xz_t90 / F_M_IJ_SCALE;
    fMom[idxMom(threadIdx.x, threadIdx.y, threadIdx.z, M_MYY_INDEX, blockIdx.x, blockIdx.y, blockIdx.z)] = m_yy_t45 / F_M_II_SCALE;
    fMom[idxMom(threadIdx.x, threadIdx.y, threadIdx.z, M_MYZ_INDEX, blockIdx.x, blockIdx.y, blockIdx.z)] = m_yz_t90 / F_M_IJ_SCALE;
    fMom[idxMom(threadIdx.x, threadIdx.y, threadIdx.z, M_MZZ_INDEX, blockIdx.x, blockIdx.y, blockIdx.z)] = m_zz_t45 / F_M_II_SCALE;
    
    #ifdef NON_NEWTONIAN_FLUID
    fMom[idxMom(threadIdx.x, threadIdx.y, threadIdx.z, M_OMEGA_INDEX, blockIdx.x, blockIdx.y, blockIdx.z)] = omegaVar;
    #endif


    if(save){
        #ifdef BC_FORCES
        //update local forces
        d_BC_Fx[idxScalarBlock(threadIdx.x, threadIdx.y, threadIdx.z,blockIdx.x, blockIdx.y, blockIdx.z)] = (L_BC_Fx);
        d_BC_Fy[idxScalarBlock(threadIdx.x, threadIdx.y, threadIdx.z,blockIdx.x, blockIdx.y, blockIdx.z)] = (L_BC_Fy);
        d_BC_Fz[idxScalarBlock(threadIdx.x, threadIdx.y, threadIdx.z,blockIdx.x, blockIdx.y, blockIdx.z)] = (L_BC_Fz);
        #endif 
    }



    #include "includeFiles/popSave"
   

}
