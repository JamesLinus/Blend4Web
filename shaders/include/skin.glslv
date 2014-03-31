#import u_frame_factor u_quatsb u_quatsa u_transb u_transa a_influence 
#import qrot

#export skin

#if SKINNED

# if SKIN_SLERP

/*
 * Ported from gl-matrix
 */
vec4 quat4_slerp(in vec4 quat, in vec4 quat2, in float slerp)
{
    float cosHalfTheta = quat[0] * quat2[0] + quat[1] * quat2[1] +
            quat[2] * quat2[2] + quat[3] * quat2[3];

    if (cosHalfTheta < 0.0) {
        quat2 *= -1.0;
        cosHalfTheta = -cosHalfTheta;
    }

    if (abs(cosHalfTheta) >= 1.0)
        return quat;

    float halfTheta = acos(cosHalfTheta);
    float sinHalfTheta = sqrt(1.0 - cosHalfTheta * cosHalfTheta);

    if (abs(sinHalfTheta) < 0.001)
        return vec4(quat * 0.5 + quat2 * 0.5);

    float ratioA = sin((1.0 - slerp) * halfTheta) / sinHalfTheta;
    float ratioB = sin(slerp * halfTheta) / sinHalfTheta;

    return quat * ratioA + quat2 * ratioB;
}

/*
vec4 quat4_normalize(vec4 quat) {
    vec4 dest;

    float x = quat[0], y = quat[1], z = quat[2], w = quat[3];

    float len = sqrt(x * x + y * y + z * z + w * w);

    if (len == 0.0) {
        dest[0] = 0.0;
        dest[1] = 0.0;
        dest[2] = 0.0;
        dest[3] = 0.0;
        return dest;
    }

    len = 1.0 / len;

    dest[0] = x * len;
    dest[1] = y * len;
    dest[2] = z * len;
    dest[3] = w * len;

    return dest;
}
*/

/*
vec4 quat4_slerp(in vec4 quat, in vec4 quat2, in float slerp) {
    // v0 and v1 should be unit length or else
    // something broken will happen.

    // Compute the cosine of the angle between the two vectors.
    float quat_dot = quat.x*quat2.x + quat.y*quat2.y + quat.z*quat2.z + quat.w*quat2.w;

    quat = quat4_normalize(quat);
    quat2 = quat4_normalize(quat2);

    if (quat_dot < -0.0) {
        quat2 *= -1.0;
        quat_dot *= -1.0;
    }

    const float DOT_THRESHOLD = 0.9995;
    if (quat_dot > DOT_THRESHOLD) {
        // If the inputs are too close for comfort, linearly interpolate
        // and normalize the result.

        vec4 result = quat + slerp*(quat2 - quat);
        quat4_normalize(result);
        return result;
    }

    clamp(quat_dot, -1.0, 1.0);           // Robustness: Stay within domain of acos()
    float theta_0 = acos(quat_dot);  // theta_0 = angle between input vectors
    float theta = theta_0*slerp;    // theta = angle between quat and result 

    vec4 v2 = quat2 - quat*quat_dot;
    quat4_normalize(v2);              // { quat, v2 } is now an orthonormal basis

    return quat*cos(theta) + v2*sin(theta);
}
*/

# endif // SKIN_SLERP

# if FRAMES_BLENDING

vec3 skin_point(in vec3 position, 
                    in vec4 quatb,
                    in vec4 quata,
                    in vec4 tranb,
                    in vec4 trana,
                    in float frame_factor) 
{
#  if SKIN_SLERP
    vec4 quat = quat4_slerp(quatb, quata, frame_factor);
    vec4 tran = mix(tranb, trana, frame_factor);

    vec3 pos_rot = qrot(quat, position);
    vec3 pos_tran_rot = pos_rot * tran.w + tran.xyz;
    return pos_tran_rot;
#  else
    vec3 pos_rot_before = qrot(quatb, position);
    vec3 pos_rot_after  = qrot(quata, position);
    // uniform scale in w, translation in xyz
    vec3 pos_tran_rot_before = pos_rot_before * tranb.w + tranb.xyz;
    vec3 pos_tran_rot_after  = pos_rot_after  * trana.w + trana.xyz;
    // blending performed AFTER quat transforms 
    // to avoid distortions on sharp angles (knees, elbows etc)
    return mix(pos_tran_rot_before, pos_tran_rot_after, frame_factor);
#  endif
}

vec3 skin_vector(in vec3 vector, 
                    in vec4 quatb,
                    in vec4 quata,
                    in float frame_factor)
{
#  if SKIN_SLERP
    vec4 quat = quat4_slerp(quatb, quata, frame_factor);
    vec3 vector_rot = qrot(quat, vector);

    return vector_rot;
#  else
    vec3 vector_rot_before = qrot(quatb, vector);
    vec3 vector_rot_after  = qrot(quata, vector);
    return mix(vector_rot_before, vector_rot_after, frame_factor);
#  endif
}

# else

vec3 skin_point(in vec3 position, 
                in vec4 quatb,
                in vec4 tranb) 
{
    vec3 pos_rot_before = qrot(quatb, position);
    // uniform scale in w, translation in xyz
    vec3 pos_tran_rot_before = pos_rot_before * tranb.w + tranb.xyz;

    return pos_tran_rot_before;
}

vec3 skin_vector(in vec3 vector, 
                     in vec4 quatb)
{
    vec3 vector_rot_before = qrot(quatb, vector);
    return vector_rot_before;
}

# endif // FRAMES_BLENDING


void skin(inout vec3 position, inout vec3 tangent, inout vec3 binormal, inout vec3 normal)
{

# if FRAMES_BLENDING
    float ff = u_frame_factor;
# endif

    // bone index is an integer part and weight is a fractional part
    if (a_influence.y > 0.0) { // sorted in descending order so no need to check others

        vec3 spos = vec3(0.0, 0.0, 0.0);
        vec3 stng = vec3(0.0, 0.0, 0.0);
        vec3 sbnr = vec3(0.0, 0.0, 0.0);
        vec3 snrm = vec3(0.0, 0.0, 0.0);

        for (int i = 0; i < 4; i++) {

            int   index  = int  (a_influence[i]);
            float weight = fract(a_influence[i]);

# if FRAMES_BLENDING
            spos += weight * skin_point(position, u_quatsb[index], u_quatsa[index], 
                    u_transb[index], u_transa[index], ff);
            stng += weight * skin_vector(tangent,  u_quatsb[index], u_quatsa[index], ff);      
            sbnr += weight * skin_vector(binormal, u_quatsb[index], u_quatsa[index], ff);
            snrm += weight * skin_vector(normal,   u_quatsb[index], u_quatsa[index], ff);        
# else
            spos += weight * skin_point(position, u_quatsb[index], u_transb[index]);
            stng += weight * skin_vector(tangent,  u_quatsb[index]);      
            sbnr += weight * skin_vector(binormal, u_quatsb[index]);
            snrm += weight * skin_vector(normal,   u_quatsb[index]);        
# endif
        }
        
        position = spos;
        tangent  = stng;
        binormal = sbnr;
        normal   = snrm;

    } else { 
        // if only one bone then weight is 1.0 
        int index = int(a_influence[0] - 1.0); // subtract 1.0 weight

        if (index > -1) { // distinguish from default zero values
# if FRAMES_BLENDING
            position = skin_point(position, u_quatsb[index], u_quatsa[index], 
                    u_transb[index], u_transa[index], ff);
            tangent  = skin_vector(tangent,  u_quatsb[index], u_quatsa[index], ff);        
            binormal = skin_vector(binormal, u_quatsb[index], u_quatsa[index], ff);
            normal   = skin_vector(normal,   u_quatsb[index], u_quatsa[index], ff);
# else
            position = skin_point(position, u_quatsb[index], u_transb[index]);
            tangent  = skin_vector(tangent,  u_quatsb[index]);        
            binormal = skin_vector(binormal, u_quatsb[index]);
            normal   = skin_vector(normal,   u_quatsb[index]);
# endif
        }
    }
}

#endif // SKINNED